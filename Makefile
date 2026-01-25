# Build mode: native, podman, docker, or auto
# - native: run commands directly on host (requires all tools installed)
# - podman: use Podman containers (default if podman available)
# - docker: use Docker containers (fallback if docker available)
# - auto: automatically detect best option using setup.sh logic
BUILD_MODE ?= auto

# Auto-detection: use setup.sh if available, otherwise native
ifeq ($(BUILD_MODE),auto)
  ifneq ($(wildcard setup.sh),)
    BUILD_MODE := $(shell ./setup.sh --detect 2>/dev/null || echo native)
  else
    BUILD_MODE := native
  endif
endif

# Container image name
IMAGE = pl0-build
FILE ?= examples/example.e0

# Configure commands based on build mode
ifeq ($(BUILD_MODE),native)
  # Native mode: run commands directly
  CXX = clang++
  KOKA = koka
  RUN =
  IMAGE_DEPS =
  $(info Build mode: NATIVE - running commands directly on host)
else ifeq ($(BUILD_MODE),podman)
  # Podman mode: use :Z for SELinux labeling
  RUN_OPTS = --rm -v $(PWD):/src:Z -w /src
  RUN = podman run $(RUN_OPTS) $(IMAGE)
  CXX = $(RUN) clang++
  KOKA = $(RUN) koka
  IMAGE_DEPS = .image
  BUILD_CMD = podman build -t $(IMAGE) .
  $(info Build mode: PODMAN - using Podman containers)
else ifeq ($(BUILD_MODE),docker)
  # Docker mode: no :Z flag (not needed/supported)
  RUN_OPTS = --rm -v $(PWD):/src -w /src
  RUN = docker run $(RUN_OPTS) $(IMAGE)
  CXX = $(RUN) clang++
  KOKA = $(RUN) koka
  IMAGE_DEPS = .image
  BUILD_CMD = docker build -t $(IMAGE) .
  $(info Build mode: DOCKER - using Docker containers)
else
  $(error Invalid BUILD_MODE: $(BUILD_MODE). Must be: auto, native, podman, or docker)
endif

# Note: timeouts must be placed *inside* the container to be effective:
#   $(RUN) timeout 5 ./e1 ...    # works
#   timeout 5 $(RUN) ./e1 ...    # does NOT work

# Build container image (only for podman/docker modes)
ifneq ($(BUILD_MODE),native)
.image: Containerfile
	$(BUILD_CMD)
	touch .image
endif
CXXSTD = -std=gnu++26
OPT = -O3 -march=native
KOKA_OPT = -O3
# For LLVM IR generation: no -march=native, as it embeds CPU-specific intrinsics
# that prevent optimization when the linked IR is compiled to native code (2x slowdown)
OPT_LLVM_IR = -O3
CXXFLAGS = $(CXXSTD) $(OPT) -Wall -Wextra -Werror -Wno-vla-cxx-extension

TARGET = e1
SRC = src/e1.cpp
HDR = src/e1.hpp

TARGET_COMPILE = e1_compile
SRC_COMPILE = src/e1_compile.cpp

$(TARGET): $(SRC) $(HDR) $(IMAGE_DEPS)
	$(CXX) $(CXXFLAGS) -o $@ $<

$(TARGET_COMPILE): $(SRC_COMPILE) $(HDR) $(IMAGE_DEPS)
	$(CXX) $(CXXFLAGS) -o $@ $<

all: $(TARGET) $(TARGET_COMPILE)

# Common compile commands for generated code
CLANGXX_OUT = clang++ $(CXXSTD) -Wno-vla-cxx-extension $(OPT) -I src
CLANG_LL = clang -Wno-override-module $(OPT)
LLVM_LINK = llvm-link /tmp/prog.ll src/e1_rt_bigint.ll -S -o out.ll

cpp-e1: $(TARGET)
	$(RUN) ./$(TARGET) examples/example.e0

cpp-e1-cpp: $(TARGET_COMPILE)
	$(RUN) sh -c "./$(TARGET_COMPILE) examples/example.e0 > out.cpp && $(CLANGXX_OUT) out.cpp -o out && ./out"

cpp-e1-llvmjit: $(TARGET_COMPILE) src/e1_rt_bigint.ll
	$(RUN) sh -c "./e1_compile --llvm examples/example.e0 > /tmp/prog.ll && $(LLVM_LINK) && lli out.ll"

cpp-e1-llvm: $(TARGET_COMPILE) src/e1_rt_bigint.ll
	$(RUN) sh -c "./e1_compile --llvm examples/example.e0 > /tmp/prog.ll && $(LLVM_LINK) && $(CLANG_LL) out.ll -o out && ./out"

src/e1_rt_bigint.ll: src/e1_rt_bigint.cpp $(IMAGE_DEPS)
	$(RUN) clang++ $(CXXSTD) -Wno-vla-cxx-extension -S -emit-llvm $(OPT_LLVM_IR) $< -o $@

clean:
	rm -rf $(TARGET) $(TARGET_COMPILE) out.ll out out.cpp out-O0 src/.koka src/e1peg src/e1 src/e2peg

BENCH_ITERS = 2000
BENCH_N = 31
BENCH_ARGS = $(BENCH_ITERS) $(BENCH_N)

bench: $(TARGET) $(TARGET_COMPILE) src/e1_rt_bigint.ll src/e1peg src/e1 src/e2peg
	@$(RUN) sh -c "./$(TARGET_COMPILE) examples/factorial.e1 > out.cpp && $(CLANGXX_OUT) out.cpp -o out_cpp"
	@echo "=== C++ backend ===" && $(RUN) sh -c "time ./out_cpp $(BENCH_ARGS)"
	@$(RUN) sh -c "./$(TARGET_COMPILE) --llvm examples/factorial.e1 > /tmp/prog.ll && $(LLVM_LINK)"
	@echo "=== LLVM backend ===" && $(RUN) sh -c "$(CLANG_LL) out.ll -o out && time ./out $(BENCH_ARGS)"
	@echo "=== LLVM lli (JIT) ===" && $(RUN) sh -c "time lli out.ll $(BENCH_ARGS)" || true
	@echo "=== C++ interpreter ===" && $(RUN) sh -c "time ./$(TARGET) examples/factorial.e1 $(BENCH_ARGS)"
	@echo "=== Koka interpreter ===" && $(RUN) sh -c "time ./src/e1 examples/factorial.e1 $(BENCH_ARGS)"
	@echo "=== Koka PEG e1 ===" && $(RUN) sh -c "time ./src/e1peg examples/factorial.e1 $(BENCH_ARGS)"
	@echo "=== Koka PEG e2 ===" && $(RUN) sh -c "time ./src/e2peg examples/factorial.e2 $(BENCH_ARGS)"

bench-1: bench

# Benchmark comparing INT_BITS settings (no Koka)
# For INT_BITS=0, also tests different LIMB_BITS values
# Note: LLVM backend may be faster for fixed INT_BITS due to loop idiom recognition
# (converts repeated addition to multiply) which _BitInt in C++ backend doesn't get
BENCH_INTBITS_BITS ?= 0 64 512
BENCH_LIMB_BITS ?= 64 32 128
bench-intbits: $(IMAGE_DEPS)
	@for bits in $(BENCH_INTBITS_BITS); do \
		if [ "$$bits" = "0" ]; then \
			for limb in $(BENCH_LIMB_BITS); do \
				echo ""; echo "========== INT_BITS=0, LIMB_BITS=$$limb =========="; \
				$(RUN) clang++ $(CXXSTD) -Wno-vla-cxx-extension -DLIMB_BITS=$$limb -S -emit-llvm $(OPT_LLVM_IR) src/e1_rt_bigint.cpp -o src/e1_rt_bigint.ll; \
				$(CXX) $(CXXFLAGS) -DINT_BITS=0 -DLIMB_BITS=$$limb -o $(TARGET) $(SRC); \
				$(CXX) $(CXXFLAGS) -DINT_BITS=0 -DLIMB_BITS=$$limb -o $(TARGET_COMPILE) $(SRC_COMPILE); \
				$(RUN) sh -c "./$(TARGET_COMPILE) $(BENCH_1) > out.cpp && $(CLANGXX_OUT) -DLIMB_BITS=$$limb out.cpp -o out_cpp"; \
				echo "=== C++ backend ===" && $(RUN) sh -c "time ./out_cpp $(BENCH_1_ARGS)"; \
				$(RUN) sh -c "./$(TARGET_COMPILE) --llvm $(BENCH_1) > /tmp/prog.ll && $(LLVM_LINK)"; \
				echo "=== LLVM backend ===" && $(RUN) sh -c "$(CLANG_LL) out.ll -o out && time ./out $(BENCH_1_ARGS)"; \
				echo "=== C++ interpreter ===" && $(RUN) sh -c "time ./$(TARGET) $(BENCH_1) $(BENCH_1_ARGS)"; \
			done; \
		else \
			echo ""; echo "========== INT_BITS=$$bits =========="; \
			$(CXX) $(CXXFLAGS) -DINT_BITS=$$bits -o $(TARGET) $(SRC); \
			$(CXX) $(CXXFLAGS) -DINT_BITS=$$bits -o $(TARGET_COMPILE) $(SRC_COMPILE); \
			$(RUN) sh -c "./$(TARGET_COMPILE) $(BENCH_1) > out.cpp && $(CLANGXX_OUT) out.cpp -o out_cpp"; \
			echo "=== C++ backend ===" && $(RUN) sh -c "time ./out_cpp $(BENCH_1_ARGS)"; \
			$(RUN) sh -c "./$(TARGET_COMPILE) --llvm $(BENCH_1) > out.ll"; \
			echo "=== LLVM backend ===" && $(RUN) sh -c "$(CLANG_LL) out.ll -o out && time ./out $(BENCH_1_ARGS)"; \
			echo "=== C++ interpreter ===" && $(RUN) sh -c "time ./$(TARGET) $(BENCH_1) $(BENCH_1_ARGS)"; \
		fi; \
	done

src/e1peg: src/e1peg.koka src/peg.koka $(IMAGE_DEPS)
	$(KOKA) $(KOKA_OPT) --compile src/peg.koka 2>/dev/null
	$(KOKA) $(KOKA_OPT) -o src/e1peg src/e1peg.koka 2>/dev/null
	chmod +x src/e1peg

src/e1: src/e1.koka src/e1-types.koka src/e1-parser.koka src/e1-eval.koka $(IMAGE_DEPS)
	$(KOKA) $(KOKA_OPT) -l src/e1-types.koka 2>/dev/null
	$(KOKA) $(KOKA_OPT) -l src/e1-parser.koka 2>/dev/null
	$(KOKA) $(KOKA_OPT) -l src/e1-eval.koka 2>/dev/null
	$(KOKA) $(KOKA_OPT) -o src/e1 src/e1.koka 2>/dev/null
	chmod +x src/e1

koka-e1: $(IMAGE_DEPS)
	$(RUN) sh -c "koka -l src/e1-types.koka && koka -l src/e1-parser.koka && koka -l src/e1-eval.koka && koka -e src/e1.koka -- $(FILE)"

koka-peg-e1: $(IMAGE_DEPS)
	$(RUN) sh -c "koka --compile src/peg.koka && koka -e src/e1peg.koka -- examples/example.e1"

koka-peg-e2: $(IMAGE_DEPS)
	$(RUN) sh -c "koka --compile src/peg.koka && koka -e src/e2peg.koka -- examples/example.e2"

src/e2peg: src/e2peg.koka src/peg.koka $(IMAGE_DEPS)
	$(KOKA) $(KOKA_OPT) --compile src/peg.koka 2>/dev/null
	$(KOKA) $(KOKA_OPT) -o src/e2peg src/e2peg.koka 2>/dev/null
	chmod +x src/e2peg

koka-peg-e0: $(IMAGE_DEPS)
	$(RUN) sh -c "koka --compile src/peg.koka && koka -e src/e0peg.koka -- examples/example.e0"

koka-peg-test: $(IMAGE_DEPS)
	$(RUN) koka -e test/peg_test.koka

# Test target: verify all examples across all interpreters/compilers
# Expected outputs use newlines (heredoc style)
test: $(TARGET) $(TARGET_COMPILE) src/e1_rt_bigint.ll src/e1peg src/e1
	@$(RUN) sh -c '\
	pass=0; fail=0; \
	check() { \
	  name="$$1"; cmd="$$2"; expected="$$3"; \
	  actual=$$(eval "$$cmd" 2>&1 | grep -E "^-?[0-9]+$$") || { echo "FAIL $$name (error)"; fail=$$((fail+1)); return; }; \
	  if [ "$$actual" = "$$expected" ]; then echo "PASS $$name"; pass=$$((pass+1)); \
	  else echo "FAIL $$name"; printf "  expected: %s\n" "$$expected" | head -1; printf "  actual: %s\n" "$$actual" | head -1; fail=$$((fail+1)); fi; \
	}; \
	./$(TARGET_COMPILE) examples/example.e0 > /tmp/out.cpp && $(CLANGXX_OUT) /tmp/out.cpp -o /tmp/out_cpp; \
	./$(TARGET_COMPILE) --llvm examples/example.e0 > /tmp/prog.ll && $(LLVM_LINK) && $(CLANG_LL) out.ll -o /tmp/out_llvm; \
	./$(TARGET_COMPILE) examples/example.e1 > /tmp/out1.cpp && $(CLANGXX_OUT) /tmp/out1.cpp -o /tmp/out1_cpp; \
	./$(TARGET_COMPILE) --llvm examples/example.e1 > /tmp/prog1.ll && llvm-link /tmp/prog1.ll src/e1_rt_bigint.ll -S -o /tmp/out1.ll && $(CLANG_LL) /tmp/out1.ll -o /tmp/out1_llvm; \
	./$(TARGET_COMPILE) examples/factorial.e1 > /tmp/fact.cpp && $(CLANGXX_OUT) /tmp/fact.cpp -o /tmp/fact_cpp; \
	./$(TARGET_COMPILE) --llvm examples/factorial.e1 > /tmp/fact.ll && llvm-link /tmp/fact.ll src/e1_rt_bigint.ll -S -o /tmp/factll.ll && $(CLANG_LL) /tmp/factll.ll -o /tmp/fact_llvm; \
	./$(TARGET_COMPILE) examples/collatz.e1 > /tmp/coll.cpp && $(CLANGXX_OUT) /tmp/coll.cpp -o /tmp/coll_cpp; \
	./$(TARGET_COMPILE) --llvm examples/collatz.e1 > /tmp/coll.ll && llvm-link /tmp/coll.ll src/e1_rt_bigint.ll -S -o /tmp/collll.ll && $(CLANG_LL) /tmp/collll.ll -o /tmp/coll_llvm; \
	./$(TARGET_COMPILE) examples/gcd.e1 > /tmp/gcd.cpp && $(CLANGXX_OUT) /tmp/gcd.cpp -o /tmp/gcd_cpp; \
	./$(TARGET_COMPILE) --llvm examples/gcd.e1 > /tmp/gcd.ll && llvm-link /tmp/gcd.ll src/e1_rt_bigint.ll -S -o /tmp/gcdll.ll && $(CLANG_LL) /tmp/gcdll.ll -o /tmp/gcd_llvm; \
	E0="7\n1\n8"; E1="6\n12\n3\n2"; COLL="5\n16\n8\n4\n2\n1"; \
	check "example_0 cpp-interp" "./$(TARGET) examples/example.e0" "$$(printf "$$E0")"; \
	check "example_0 cpp-backend" "/tmp/out_cpp" "$$(printf "$$E0")"; \
	check "example_0 llvm-backend" "/tmp/out_llvm" "$$(printf "$$E0")"; \
	check "example_0 koka" "./src/e1 examples/example.e0" "$$(printf "$$E0")"; \
	check "example_0 koka-peg" "./src/e1peg examples/example.e0" "$$(printf "$$E0")"; \
	check "example_1 cpp-interp" "./$(TARGET) examples/example.e1" "$$(printf "$$E1")"; \
	check "example_1 cpp-backend" "/tmp/out1_cpp" "$$(printf "$$E1")"; \
	check "example_1 llvm-backend" "/tmp/out1_llvm" "$$(printf "$$E1")"; \
	check "example_1 koka" "./src/e1 examples/example.e1" "$$(printf "$$E1")"; \
	check "example_1 koka-peg" "./src/e1peg examples/example.e1" "$$(printf "$$E1")"; \
	check "factorial cpp-interp" "./$(TARGET) examples/factorial.e1 1 5" "120"; \
	check "factorial cpp-backend" "/tmp/fact_cpp 1 5" "120"; \
	check "factorial llvm-backend" "/tmp/fact_llvm 1 5" "120"; \
	check "factorial koka" "./src/e1 examples/factorial.e1 1 5" "120"; \
	check "factorial koka-peg" "./src/e1peg examples/factorial.e1 1 5" "120"; \
	check "collatz cpp-interp" "./$(TARGET) examples/collatz.e1 5" "$$(printf "$$COLL")"; \
	check "collatz cpp-backend" "/tmp/coll_cpp 5" "$$(printf "$$COLL")"; \
	check "collatz llvm-backend" "/tmp/coll_llvm 5" "$$(printf "$$COLL")"; \
	check "collatz koka" "./src/e1 examples/collatz.e1 5" "$$(printf "$$COLL")"; \
	check "collatz koka-peg" "./src/e1peg examples/collatz.e1 5" "$$(printf "$$COLL")"; \
	check "gcd cpp-interp" "./$(TARGET) examples/gcd.e1 48 18" "6"; \
	check "gcd cpp-backend" "/tmp/gcd_cpp 48 18" "6"; \
	check "gcd llvm-backend" "/tmp/gcd_llvm 48 18" "6"; \
	check "gcd koka" "./src/e1 examples/gcd.e1 48 18" "6"; \
	check "gcd koka-peg" "./src/e1peg examples/gcd.e1 48 18" "6"; \
	echo ""; echo "Results: $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]'

# Help target
help:
	@echo "Build modes: auto (default), native, podman, docker"
	@echo "Current: $(BUILD_MODE)"
	@echo ""
	@echo "Usage: make [BUILD_MODE=<mode>] [target]"
	@echo ""
	@echo "Run targets:"
	@echo "  cpp-e1         C++ interpreter (e1)"
	@echo "  cpp-e1-cpp     C++ compiler, C++ backend (e1)"
	@echo "  cpp-e1-llvm    C++ compiler, LLVM native (e1)"
	@echo "  cpp-e1-llvmjit C++ compiler, LLVM JIT (e1)"
	@echo "  koka-e1        Koka interpreter (e1)"
	@echo "  koka-peg-e0    Koka PEG interpreter (e0)"
	@echo "  koka-peg-e1    Koka PEG interpreter (e1)"
	@echo "  koka-peg-e2    Koka PEG interpreter (e2)"
	@echo ""
	@echo "Other: all, test, bench, bench-intbits, clean"

.PHONY: cpp-e1 cpp-e1-cpp cpp-e1-llvm cpp-e1-llvmjit clean bench bench-intbits koka-e1 koka-peg-e0 koka-peg-e1 koka-peg-e2 koka-peg-test test help

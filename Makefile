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
FILE ?= examples/example_0.pl0

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
#   $(RUN) timeout 5 ./pl0_1 ...    # works
#   timeout 5 $(RUN) ./pl0_1 ...    # does NOT work

# Build container image (only for podman/docker modes)
ifneq ($(BUILD_MODE),native)
.image: Containerfile
	$(BUILD_CMD)
	touch .image
endif
CXXFLAGS = -std=gnu++26 -Wall -Wextra -Werror

TARGET = pl0_1
SRC = src/pl0_1.cpp
HDR = src/pl0_1.hpp

TARGET_COMPILE = pl0_1_compile
SRC_COMPILE = src/pl0_1_compile.cpp

$(TARGET): $(SRC) $(HDR) $(IMAGE_DEPS)
	$(CXX) $(CXXFLAGS) -O3 -o $@ $<

$(TARGET_COMPILE): $(SRC_COMPILE) $(HDR) $(IMAGE_DEPS)
	$(CXX) $(CXXFLAGS) -O3 -o $@ $<

all: $(TARGET) $(TARGET_COMPILE)

run: $(TARGET)
	$(RUN) ./$(TARGET) examples/example_0.pl0

run-compile: $(TARGET_COMPILE)
	$(RUN) sh -c "./$(TARGET_COMPILE) examples/example_0.pl0 > out.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 out.cpp -o out && ./out"

LLVM_LINK = llvm-link /tmp/prog.ll src/pl0_1_rt_bigint.ll -S -o out.ll

run-llvm: $(TARGET_COMPILE) src/pl0_1_rt_bigint.ll
	$(RUN) sh -c "./pl0_1_compile --llvm examples/example_0.pl0 > /tmp/prog.ll && $(LLVM_LINK) && lli out.ll"

run-llvm-native: $(TARGET_COMPILE) src/pl0_1_rt_bigint.ll
	$(RUN) sh -c "./pl0_1_compile --llvm examples/example_0.pl0 > /tmp/prog.ll && $(LLVM_LINK) && clang -Wno-override-module -O3 out.ll -o out && ./out"

src/pl0_1_rt_bigint.ll: src/pl0_1_rt_bigint.cpp $(IMAGE_DEPS)
	$(RUN) clang++ -std=c++26 -S -emit-llvm -O3 $< -o $@

clean:
	rm -rf $(TARGET) $(TARGET_COMPILE) out.ll out out.cpp out-O0 src/.koka src/pl0peg1 src/pl01

BENCH_1 = examples/bench_1_factorial.pl0
BENCH_1_ARGS = 2000 31

bench-1: $(TARGET) $(TARGET_COMPILE) src/pl0_1_rt_bigint.ll src/pl0peg1 src/pl01
	@# All compiled code uses -O3 optimization
	@$(RUN) sh -c "./$(TARGET_COMPILE) $(BENCH_1) > out.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src out.cpp -o out_cpp"
	@echo "=== C++ backend ===" && $(RUN) sh -c "time ./out_cpp $(BENCH_1_ARGS)"
	@$(RUN) sh -c "./$(TARGET_COMPILE) --llvm $(BENCH_1) > /tmp/prog.ll && $(LLVM_LINK)"
	@echo "=== LLVM backend ===" && $(RUN) sh -c "clang -Wno-override-module -O3 out.ll -o out && time ./out $(BENCH_1_ARGS)"
	@echo "=== LLVM lli (JIT) ===" && $(RUN) sh -c "time lli out.ll $(BENCH_1_ARGS)" || true
	@echo "=== C++ interpreter ===" && $(RUN) sh -c "time ./$(TARGET) $(BENCH_1) $(BENCH_1_ARGS)"
	@echo "=== Koka interpreter ===" && $(RUN) sh -c "time ./src/pl01 $(BENCH_1) $(BENCH_1_ARGS)"
	@echo "=== Koka PEG interpreter ===" && $(RUN) sh -c "time ./src/pl0peg1 $(BENCH_1) $(BENCH_1_ARGS)"

src/pl0peg1: src/pl0peg1.koka src/peg.koka $(IMAGE_DEPS)
	$(KOKA) -O3 --compile src/peg.koka 2>/dev/null
	$(KOKA) -O3 -o src/pl0peg1 src/pl0peg1.koka 2>/dev/null
	chmod +x src/pl0peg1

src/pl01: src/pl01.koka src/pl01-types.koka src/pl01-parser.koka src/pl01-eval.koka $(IMAGE_DEPS)
	$(KOKA) -O3 -l src/pl01-types.koka 2>/dev/null
	$(KOKA) -O3 -l src/pl01-parser.koka 2>/dev/null
	$(KOKA) -O3 -l src/pl01-eval.koka 2>/dev/null
	$(KOKA) -O3 -o src/pl01 src/pl01.koka 2>/dev/null
	chmod +x src/pl01

koka-pl0: $(IMAGE_DEPS)
	$(RUN) sh -c "koka -l src/pl01-types.koka && koka -l src/pl01-parser.koka && koka -l src/pl01-eval.koka && koka -e src/pl01.koka -- $(FILE)"

koka-peg: $(IMAGE_DEPS)
	$(RUN) sh -c "koka --compile src/peg.koka && koka -e src/pl0peg1.koka -- examples/example_0.pl0"

koka-peg0: $(IMAGE_DEPS)
	$(RUN) sh -c "koka --compile src/peg.koka && koka -e src/pl0peg0.koka -- examples/example_0.pl0"

koka-peg-test: $(IMAGE_DEPS)
	$(RUN) koka -e test/peg_test.koka

# Test target: verify all examples across all interpreters/compilers
# Expected outputs use newlines (heredoc style)
test: $(TARGET) $(TARGET_COMPILE) src/pl0_1_rt_bigint.ll src/pl0peg1 src/pl01
	@$(RUN) sh -c '\
	pass=0; fail=0; \
	check() { \
	  name="$$1"; cmd="$$2"; expected="$$3"; \
	  actual=$$(eval "$$cmd" 2>&1 | grep -E "^-?[0-9]+$$") || { echo "FAIL $$name (error)"; fail=$$((fail+1)); return; }; \
	  if [ "$$actual" = "$$expected" ]; then echo "PASS $$name"; pass=$$((pass+1)); \
	  else echo "FAIL $$name"; printf "  expected: %s\n" "$$expected" | head -1; printf "  actual: %s\n" "$$actual" | head -1; fail=$$((fail+1)); fi; \
	}; \
	./$(TARGET_COMPILE) examples/example_0.pl0 > /tmp/out.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src /tmp/out.cpp -o /tmp/out_cpp; \
	./$(TARGET_COMPILE) --llvm examples/example_0.pl0 > /tmp/prog.ll && $(LLVM_LINK) && clang -Wno-override-module -O3 out.ll -o /tmp/out_llvm; \
	./$(TARGET_COMPILE) examples/example_1.pl0 > /tmp/out1.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src /tmp/out1.cpp -o /tmp/out1_cpp; \
	./$(TARGET_COMPILE) --llvm examples/example_1.pl0 > /tmp/prog1.ll && llvm-link /tmp/prog1.ll src/pl0_1_rt_bigint.ll -S -o /tmp/out1.ll && clang -Wno-override-module -O3 /tmp/out1.ll -o /tmp/out1_llvm; \
	./$(TARGET_COMPILE) examples/bench_1_factorial.pl0 > /tmp/fact.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src /tmp/fact.cpp -o /tmp/fact_cpp; \
	./$(TARGET_COMPILE) --llvm examples/bench_1_factorial.pl0 > /tmp/fact.ll && llvm-link /tmp/fact.ll src/pl0_1_rt_bigint.ll -S -o /tmp/factll.ll && clang -Wno-override-module -O3 /tmp/factll.ll -o /tmp/fact_llvm; \
	./$(TARGET_COMPILE) examples/collatz_1.pl0 > /tmp/coll.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src /tmp/coll.cpp -o /tmp/coll_cpp; \
	./$(TARGET_COMPILE) --llvm examples/collatz_1.pl0 > /tmp/coll.ll && llvm-link /tmp/coll.ll src/pl0_1_rt_bigint.ll -S -o /tmp/collll.ll && clang -Wno-override-module -O3 /tmp/collll.ll -o /tmp/coll_llvm; \
	./$(TARGET_COMPILE) examples/gcd_1.pl0 > /tmp/gcd.cpp && clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src /tmp/gcd.cpp -o /tmp/gcd_cpp; \
	./$(TARGET_COMPILE) --llvm examples/gcd_1.pl0 > /tmp/gcd.ll && llvm-link /tmp/gcd.ll src/pl0_1_rt_bigint.ll -S -o /tmp/gcdll.ll && clang -Wno-override-module -O3 /tmp/gcdll.ll -o /tmp/gcd_llvm; \
	E0="7\n1\n8"; E1="6\n12\n3\n2"; COLL="5\n16\n8\n4\n2\n1"; \
	check "example_0 cpp-interp" "./$(TARGET) examples/example_0.pl0" "$$(printf "$$E0")"; \
	check "example_0 cpp-backend" "/tmp/out_cpp" "$$(printf "$$E0")"; \
	check "example_0 llvm-backend" "/tmp/out_llvm" "$$(printf "$$E0")"; \
	check "example_0 koka" "./src/pl01 examples/example_0.pl0" "$$(printf "$$E0")"; \
	check "example_0 koka-peg" "./src/pl0peg1 examples/example_0.pl0" "$$(printf "$$E0")"; \
	check "example_1 cpp-interp" "./$(TARGET) examples/example_1.pl0" "$$(printf "$$E1")"; \
	check "example_1 cpp-backend" "/tmp/out1_cpp" "$$(printf "$$E1")"; \
	check "example_1 llvm-backend" "/tmp/out1_llvm" "$$(printf "$$E1")"; \
	check "example_1 koka" "./src/pl01 examples/example_1.pl0" "$$(printf "$$E1")"; \
	check "example_1 koka-peg" "./src/pl0peg1 examples/example_1.pl0" "$$(printf "$$E1")"; \
	check "factorial cpp-interp" "./$(TARGET) examples/bench_1_factorial.pl0 1 5" "120"; \
	check "factorial cpp-backend" "/tmp/fact_cpp 1 5" "120"; \
	check "factorial llvm-backend" "/tmp/fact_llvm 1 5" "120"; \
	check "factorial koka" "./src/pl01 examples/bench_1_factorial.pl0 1 5" "120"; \
	check "factorial koka-peg" "./src/pl0peg1 examples/bench_1_factorial.pl0 1 5" "120"; \
	check "collatz cpp-interp" "./$(TARGET) examples/collatz_1.pl0 5" "$$(printf "$$COLL")"; \
	check "collatz cpp-backend" "/tmp/coll_cpp 5" "$$(printf "$$COLL")"; \
	check "collatz llvm-backend" "/tmp/coll_llvm 5" "$$(printf "$$COLL")"; \
	check "collatz koka" "./src/pl01 examples/collatz_1.pl0 5" "$$(printf "$$COLL")"; \
	check "collatz koka-peg" "./src/pl0peg1 examples/collatz_1.pl0 5" "$$(printf "$$COLL")"; \
	check "gcd cpp-interp" "./$(TARGET) examples/gcd_1.pl0 48 18" "6"; \
	check "gcd cpp-backend" "/tmp/gcd_cpp 48 18" "6"; \
	check "gcd llvm-backend" "/tmp/gcd_llvm 48 18" "6"; \
	check "gcd koka" "./src/pl01 examples/gcd_1.pl0 48 18" "6"; \
	check "gcd koka-peg" "./src/pl0peg1 examples/gcd_1.pl0 48 18" "6"; \
	echo ""; echo "Results: $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]'

# Help target
help:
	@echo "Build modes: auto (default), native, podman, docker"
	@echo "Current: $(BUILD_MODE)"
	@echo ""
	@echo "Usage: make [BUILD_MODE=<mode>] [target]"
	@echo "Targets: all, test, bench-1, clean, help"
	@echo ""
	@echo "Setup: . ./setup.sh  (or run ./setup.sh for info)"

.PHONY: run run-llvm run-llvm-native clean bench-1 koka-pl0 koka-peg koka-peg0 koka-peg-test test help

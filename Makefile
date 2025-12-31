IMAGE = pl0-build
RUN_OPTS = --rm -v $(PWD):/src:Z -w /src
CXX = podman run $(RUN_OPTS) $(IMAGE) g++
KOKA = podman run $(RUN_OPTS) $(IMAGE) koka

.image: Containerfile
	podman build -t $(IMAGE) .
	touch .image
CXXFLAGS = -std=gnu++26 -Wall -Wextra -Werror

TARGET = pl0_1
SRC = src/pl0_1.cpp

TARGET_LLVM = pl0_1_llvm
SRC_LLVM = src/pl0_1_llvm.cpp

$(TARGET): $(SRC) | .image
	$(CXX) $(CXXFLAGS) -O3 -o $@ $<

$(TARGET_LLVM): $(SRC_LLVM) | .image
	$(CXX) $(CXXFLAGS) -O3 -o $@ $<

all: $(TARGET) $(TARGET_LLVM)

run: $(TARGET)
	$(RUN) ./$(TARGET) examples/example_0.pl0

run-llvm: $(TARGET_LLVM)
	$(RUN) sh -c "./$(TARGET_LLVM) examples/example_0.pl0 > out.ll && lli out.ll"

run-llvm-native: $(TARGET_LLVM)
	$(RUN) sh -c "./$(TARGET_LLVM) examples/example_0.pl0 > out.ll && clang -Wno-override-module -O3 out.ll -o out && ./out"

clean:
	rm -rf $(TARGET) $(TARGET_LLVM) out.ll out out-O0 src/.koka src/pl0peg1 src/pl01

BENCH_1 = examples/bench_1_factorial.pl0
BENCH_1_ARGS = 2000 31
RUN = podman run $(RUN_OPTS) $(IMAGE)

bench-1: $(TARGET) $(TARGET_LLVM) src/pl0peg1 src/pl01
	@$(RUN) sh -c "./$(TARGET_LLVM) $(BENCH_1) > out.ll"
	@echo "=== lli (JIT) ===" && $(RUN) sh -c "time lli out.ll $(BENCH_1_ARGS)" || true
	@echo "=== clang -O0 ===" && $(RUN) sh -c "clang -Wno-override-module -O0 out.ll -o out-O0 && time ./out-O0 $(BENCH_1_ARGS)"
	@echo "=== clang -O3 ===" && $(RUN) sh -c "clang -Wno-override-module -O3 out.ll -o out && time ./out $(BENCH_1_ARGS)"
	@echo "=== C++ interpreter ===" && $(RUN) sh -c "time ./$(TARGET) $(BENCH_1) $(BENCH_1_ARGS)"
	@echo "=== koka -O3 ===" && $(RUN) sh -c "time ./src/pl01 $(BENCH_1) $(BENCH_1_ARGS)"
	@echo "=== koka -O3 (PEG) ===" && $(RUN) sh -c "time ./src/pl0peg1 $(BENCH_1) $(BENCH_1_ARGS)"

src/pl0peg1: src/pl0peg1.koka src/peg.koka | .image
	$(KOKA) -O3 --compile src/peg.koka 2>/dev/null
	$(KOKA) -O3 -o src/pl0peg1 src/pl0peg1.koka 2>/dev/null
	chmod +x src/pl0peg1

src/pl01: src/pl01.koka src/pl01-types.koka src/pl01-parser.koka src/pl01-eval.koka | .image
	$(KOKA) -O3 -l src/pl01-types.koka 2>/dev/null
	$(KOKA) -O3 -l src/pl01-parser.koka 2>/dev/null
	$(KOKA) -O3 -l src/pl01-eval.koka 2>/dev/null
	$(KOKA) -O3 -o src/pl01 src/pl01.koka 2>/dev/null
	chmod +x src/pl01

koka-pl0: | .image
	$(RUN) koka -e src/pl01.koka -- examples/example_0.pl0

koka-peg: | .image
	$(RUN) sh -c "koka --compile src/peg.koka && koka -e src/pl0peg1.koka -- examples/example_0.pl0"

koka-peg-test: | .image
	$(RUN) koka -e test/peg_test.koka

.PHONY: run run-llvm run-llvm-native clean bench-1 koka-pl0 koka-peg koka-peg-test

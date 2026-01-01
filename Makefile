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

TARGET_COMPILE = pl0_1_compile
SRC_COMPILE = src/pl0_1_compile.cpp

$(TARGET): $(SRC) | .image
	$(CXX) $(CXXFLAGS) -O3 -o $@ $<

$(TARGET_COMPILE): $(SRC_COMPILE) | .image
	$(CXX) $(CXXFLAGS) -O3 -o $@ $<

all: $(TARGET) $(TARGET_COMPILE)

run: $(TARGET)
	$(RUN) ./$(TARGET) examples/example_0.pl0

run-compile: $(TARGET_COMPILE)
	$(RUN) sh -c "./$(TARGET_COMPILE) examples/example_0.pl0 > out.cpp && g++ -std=gnu++26 -O3 out.cpp -o out && ./out"

LLVM_LINK = llvm-link /tmp/prog.ll src/pl0_1_rt_bigint.bc -S -o out.ll

run-llvm: $(TARGET_COMPILE) src/pl0_1_rt_bigint.bc
	$(RUN) sh -c "./pl0_1_compile --llvm examples/example_0.pl0 > /tmp/prog.ll && $(LLVM_LINK) && lli -load /lib64/libstdc++.so.6 out.ll"

run-llvm-native: $(TARGET_COMPILE) src/pl0_1_rt_bigint.bc
	$(RUN) sh -c "./pl0_1_compile --llvm examples/example_0.pl0 > /tmp/prog.ll && $(LLVM_LINK) && clang++ -Wno-override-module -O3 out.ll -o out && ./out"

src/pl0_1_rt_bigint.bc: src/pl0_1_rt_bigint.cpp | .image
	$(CXX) -c -emit-llvm -Oz -fno-exceptions -fno-rtti $< -o $@

clean:
	rm -rf $(TARGET) $(TARGET_COMPILE) out.ll out out.cpp out-O0 src/.koka src/pl0peg1 src/pl01

BENCH_1 = examples/bench_1_factorial.pl0
BENCH_1_ARGS = 2000 31
RUN = podman run $(RUN_OPTS) $(IMAGE)

bench-1: $(TARGET) $(TARGET_COMPILE) src/pl0_1_rt_bigint.bc src/pl0peg1 src/pl01
	@$(RUN) sh -c "./$(TARGET_COMPILE) $(BENCH_1) > out.cpp && g++ -std=gnu++26 -O3 out.cpp -o out_cpp"
	@echo "=== C++ backend -O3 ===" && $(RUN) sh -c "time ./out_cpp $(BENCH_1_ARGS)"
	@$(RUN) sh -c "./$(TARGET_COMPILE) --llvm $(BENCH_1) > /tmp/prog.ll && $(LLVM_LINK)"
	@echo "=== lli (JIT) ===" && $(RUN) sh -c "time lli -load /lib64/libstdc++.so.6 out.ll $(BENCH_1_ARGS)" || true
	@echo "=== clang -O0 ===" && $(RUN) sh -c "clang++ -Wno-override-module -O0 out.ll -o out-O0 && time ./out-O0 $(BENCH_1_ARGS)"
	@echo "=== clang -O3 ===" && $(RUN) sh -c "clang++ -Wno-override-module -O3 out.ll -o out && time ./out $(BENCH_1_ARGS)"
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

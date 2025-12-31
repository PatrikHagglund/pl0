; PL/0 Level 1 Runtime Library (LLVM IR)

declare i32 @putchar(i32)
declare i64 @strtol(ptr, ptr, i32)

define void @print_i128_rec(i128 %v) {
  %z = icmp eq i128 %v, 0
  br i1 %z, label %done, label %print
print:
  %div = sdiv i128 %v, 10
  %rem = srem i128 %v, 10
  call void @print_i128_rec(i128 %div)
  %d = trunc i128 %rem to i32
  %c = add i32 %d, 48
  call i32 @putchar(i32 %c)
  br label %done
done:
  ret void
}

define void @print_i128(i128 %v) {
  %z = icmp eq i128 %v, 0
  br i1 %z, label %zero, label %nonzero
zero:
  call i32 @putchar(i32 48)
  br label %done
nonzero:
  call void @print_i128_rec(i128 %v)
  br label %done
done:
  call i32 @putchar(i32 10)
  ret void
}

define i128 @parse_arg(i32 %argc, ptr %argv, i32 %idx) {
  %has = icmp sgt i32 %argc, %idx
  br i1 %has, label %read, label %default
read:
  %i = sext i32 %idx to i64
  %p = getelementptr ptr, ptr %argv, i64 %i
  %s = load ptr, ptr %p
  %v64 = call i64 @strtol(ptr %s, ptr null, i32 10)
  %v = sext i64 %v64 to i128
  ret i128 %v
default:
  ret i128 0
}

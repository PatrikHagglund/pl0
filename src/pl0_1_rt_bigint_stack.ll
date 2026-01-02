; ModuleID = 'src/pl0_1_rt_bigint_stack.cpp'
source_filename = "src/pl0_1_rt_bigint_stack.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-redhat-linux-gnu"

@stdout = external dso_local local_unnamed_addr global ptr, align 8

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: write) uwtable
define dso_local void @bi_init(ptr noundef writeonly captures(none) initializes((0, 8)) %0, i64 noundef %1) local_unnamed_addr #0 {
  %3 = lshr i64 %1, 63
  %4 = trunc nuw nsw i64 %3 to i32
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 %4, ptr %5, align 4, !tbaa !3
  %6 = icmp eq i64 %1, 0
  br i1 %6, label %10, label %7

7:                                                ; preds = %2
  %8 = tail call i64 @llvm.abs.i64(i64 %1, i1 true)
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 %8, ptr %9, align 8, !tbaa !7
  br label %10

10:                                               ; preds = %2, %7
  %11 = phi i32 [ 1, %7 ], [ 0, %2 ]
  store i32 %11, ptr %0, align 8, !tbaa !3
  ret void
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr captures(none)) #1

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr captures(none)) #1

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite) uwtable
define dso_local void @bi_copy(ptr noundef writeonly captures(none) initializes((0, 8)) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #2 {
  %3 = load i32, ptr %1, align 8, !tbaa !3
  store i32 %3, ptr %0, align 8, !tbaa !3
  %4 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %5 = load i32, ptr %4, align 4, !tbaa !3
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 %5, ptr %6, align 4, !tbaa !3
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %8 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %9 = load i32, ptr %1, align 8, !tbaa !3
  %10 = sext i32 %9 to i64
  %11 = shl nsw i64 %10, 3
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %7, ptr nonnull align 8 %8, i64 %11, i1 false)
  ret void
}

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #3

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local range(i32 -2147483647, -2147483648) i32 @bi_add_size(ptr noundef readonly captures(none) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #4 {
  %3 = load i32, ptr %0, align 8, !tbaa !3
  %4 = load i32, ptr %1, align 8, !tbaa !3
  %5 = tail call i32 @llvm.smax.i32(i32 %3, i32 %4)
  %6 = add nsw i32 %5, 1
  ret i32 %6
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local range(i32 -2147483647, -2147483648) i32 @bi_sub_size(ptr noundef readonly captures(none) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #4 {
  %3 = load i32, ptr %0, align 8, !tbaa !3
  %4 = load i32, ptr %1, align 8, !tbaa !3
  %5 = tail call i32 @llvm.smax.i32(i32 %3, i32 %4)
  %6 = add nsw i32 %5, 1
  ret i32 %6
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local i32 @bi_neg_size(ptr noundef readonly captures(none) %0) local_unnamed_addr #4 {
  %2 = load i32, ptr %0, align 8, !tbaa !3
  ret i32 %2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none) uwtable
define dso_local void @bi_add(ptr noundef captures(none) %0, ptr noundef readonly captures(none) %1, ptr noundef readonly captures(none) %2) local_unnamed_addr #5 {
  %4 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %5 = load i32, ptr %4, align 4, !tbaa !3
  %6 = getelementptr inbounds nuw i8, ptr %2, i64 4
  %7 = load i32, ptr %6, align 4, !tbaa !3
  %8 = icmp eq i32 %5, %7
  %9 = load i32, ptr %1, align 8, !tbaa !3
  %10 = load i32, ptr %2, align 8, !tbaa !3
  br i1 %8, label %11, label %52

11:                                               ; preds = %3
  %12 = tail call i32 @llvm.smax.i32(i32 %9, i32 %10)
  %13 = icmp sgt i32 %12, 0
  br i1 %13, label %14, label %227

14:                                               ; preds = %11
  %15 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %16 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %18 = sext i32 %9 to i64
  %19 = sext i32 %10 to i64
  %20 = zext nneg i32 %12 to i64
  br label %23

21:                                               ; preds = %36
  %22 = icmp eq i64 %46, 0
  br i1 %22, label %227, label %49

23:                                               ; preds = %36, %14
  %24 = phi i64 [ 0, %14 ], [ %47, %36 ]
  %25 = phi i64 [ 0, %14 ], [ %46, %36 ]
  %26 = icmp slt i64 %24, %18
  br i1 %26, label %27, label %30

27:                                               ; preds = %23
  %28 = getelementptr inbounds nuw [0 x i64], ptr %15, i64 0, i64 %24
  %29 = load i64, ptr %28, align 8, !tbaa !7
  br label %30

30:                                               ; preds = %27, %23
  %31 = phi i64 [ %29, %27 ], [ 0, %23 ]
  %32 = icmp slt i64 %24, %19
  br i1 %32, label %33, label %36

33:                                               ; preds = %30
  %34 = getelementptr inbounds nuw [0 x i64], ptr %16, i64 0, i64 %24
  %35 = load i64, ptr %34, align 8, !tbaa !7
  br label %36

36:                                               ; preds = %33, %30
  %37 = phi i64 [ %35, %33 ], [ 0, %30 ]
  %38 = zext i64 %31 to i128
  %39 = zext i64 %37 to i128
  %40 = zext nneg i64 %25 to i128
  %41 = add nuw nsw i128 %38, %40
  %42 = add nuw nsw i128 %41, %39
  %43 = trunc i128 %42 to i64
  %44 = getelementptr inbounds nuw [0 x i64], ptr %17, i64 0, i64 %24
  store i64 %43, ptr %44, align 8, !tbaa !7
  %45 = lshr i128 %42, 64
  %46 = trunc nuw nsw i128 %45 to i64
  %47 = add nuw nsw i64 %24, 1
  %48 = icmp eq i64 %47, %20
  br i1 %48, label %21, label %23, !llvm.loop !9

49:                                               ; preds = %21
  %50 = getelementptr inbounds nuw [0 x i64], ptr %17, i64 0, i64 %20
  store i64 1, ptr %50, align 8, !tbaa !7
  %51 = add nuw nsw i32 %12, 1
  br label %227

52:                                               ; preds = %3
  %53 = icmp eq i32 %9, %10
  br i1 %53, label %54, label %58

54:                                               ; preds = %52
  %55 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %56 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %57 = zext i32 %9 to i64
  br label %60

58:                                               ; preds = %52
  %59 = icmp sgt i32 %9, %10
  br i1 %59, label %73, label %150

60:                                               ; preds = %64, %54
  %61 = phi i64 [ %57, %54 ], [ %65, %64 ]
  %62 = trunc nuw i64 %61 to i32
  %63 = icmp slt i32 %62, 1
  br i1 %63, label %73, label %64

64:                                               ; preds = %60
  %65 = add nsw i64 %61, -1
  %66 = getelementptr inbounds nuw [0 x i64], ptr %55, i64 0, i64 %65
  %67 = load i64, ptr %66, align 8, !tbaa !7
  %68 = getelementptr inbounds nuw [0 x i64], ptr %56, i64 0, i64 %65
  %69 = load i64, ptr %68, align 8, !tbaa !7
  %70 = icmp eq i64 %67, %69
  br i1 %70, label %60, label %71, !llvm.loop !11

71:                                               ; preds = %64
  %72 = icmp ugt i64 %67, %69
  br i1 %72, label %73, label %150

73:                                               ; preds = %60, %71, %58
  %74 = icmp sgt i32 %9, 0
  br i1 %74, label %77, label %75

75:                                               ; preds = %73
  %76 = zext i32 %9 to i64
  br label %103

77:                                               ; preds = %73
  %78 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %79 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %80 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %81 = sext i32 %10 to i64
  %82 = zext nneg i32 %9 to i64
  %83 = and i64 %82, 1
  %84 = icmp eq i32 %9, 1
  br i1 %84, label %87, label %85

85:                                               ; preds = %77
  %86 = and i64 %82, 2147483646
  br label %107

87:                                               ; preds = %131, %77
  %88 = phi i64 [ 0, %77 ], [ %138, %131 ]
  %89 = phi i64 [ 0, %77 ], [ %136, %131 ]
  %90 = icmp eq i64 %83, 0
  br i1 %90, label %103, label %91

91:                                               ; preds = %87
  %92 = getelementptr inbounds nuw [0 x i64], ptr %78, i64 0, i64 %88
  %93 = load i64, ptr %92, align 8, !tbaa !7
  %94 = icmp slt i64 %88, %81
  br i1 %94, label %95, label %98

95:                                               ; preds = %91
  %96 = getelementptr inbounds nuw [0 x i64], ptr %79, i64 0, i64 %88
  %97 = load i64, ptr %96, align 8, !tbaa !7
  br label %98

98:                                               ; preds = %95, %91
  %99 = phi i64 [ %97, %95 ], [ 0, %91 ]
  %100 = add i64 %99, %89
  %101 = sub i64 %93, %100
  %102 = getelementptr inbounds nuw [0 x i64], ptr %80, i64 0, i64 %88
  store i64 %101, ptr %102, align 8, !tbaa !7
  br label %103

103:                                              ; preds = %98, %87, %75
  %104 = phi i64 [ %76, %75 ], [ %82, %87 ], [ %82, %98 ]
  %105 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %106 = tail call i32 @llvm.smin.i32(i32 %9, i32 0)
  br label %141

107:                                              ; preds = %131, %85
  %108 = phi i64 [ 0, %85 ], [ %138, %131 ]
  %109 = phi i64 [ 0, %85 ], [ %136, %131 ]
  %110 = phi i64 [ 0, %85 ], [ %139, %131 ]
  %111 = getelementptr inbounds nuw [0 x i64], ptr %78, i64 0, i64 %108
  %112 = load i64, ptr %111, align 8, !tbaa !7
  %113 = icmp slt i64 %108, %81
  br i1 %113, label %114, label %117

114:                                              ; preds = %107
  %115 = getelementptr inbounds nuw [0 x i64], ptr %79, i64 0, i64 %108
  %116 = load i64, ptr %115, align 8, !tbaa !7
  br label %117

117:                                              ; preds = %114, %107
  %118 = phi i64 [ %116, %114 ], [ 0, %107 ]
  %119 = add i64 %118, %109
  %120 = sub i64 %112, %119
  %121 = icmp ult i64 %112, %119
  %122 = zext i1 %121 to i64
  %123 = getelementptr inbounds nuw [0 x i64], ptr %80, i64 0, i64 %108
  store i64 %120, ptr %123, align 8, !tbaa !7
  %124 = or disjoint i64 %108, 1
  %125 = getelementptr inbounds nuw [0 x i64], ptr %78, i64 0, i64 %124
  %126 = load i64, ptr %125, align 8, !tbaa !7
  %127 = icmp slt i64 %124, %81
  br i1 %127, label %128, label %131

128:                                              ; preds = %117
  %129 = getelementptr inbounds nuw [0 x i64], ptr %79, i64 0, i64 %124
  %130 = load i64, ptr %129, align 8, !tbaa !7
  br label %131

131:                                              ; preds = %128, %117
  %132 = phi i64 [ %130, %128 ], [ 0, %117 ]
  %133 = add i64 %132, %122
  %134 = sub i64 %126, %133
  %135 = icmp ult i64 %126, %133
  %136 = zext i1 %135 to i64
  %137 = getelementptr inbounds nuw [0 x i64], ptr %80, i64 0, i64 %124
  store i64 %134, ptr %137, align 8, !tbaa !7
  %138 = add nuw nsw i64 %108, 2
  %139 = add i64 %110, 2
  %140 = icmp eq i64 %139, %86
  br i1 %140, label %87, label %107, !llvm.loop !12

141:                                              ; preds = %145, %103
  %142 = phi i64 [ %104, %103 ], [ %146, %145 ]
  %143 = trunc nuw i64 %142 to i32
  %144 = icmp sgt i32 %143, 0
  br i1 %144, label %145, label %227

145:                                              ; preds = %141
  %146 = add nsw i64 %142, -1
  %147 = getelementptr inbounds nuw [0 x i64], ptr %105, i64 0, i64 %146
  %148 = load i64, ptr %147, align 8, !tbaa !7
  %149 = icmp eq i64 %148, 0
  br i1 %149, label %141, label %227, !llvm.loop !13

150:                                              ; preds = %58, %71
  %151 = icmp sgt i32 %10, 0
  br i1 %151, label %154, label %152

152:                                              ; preds = %150
  %153 = zext i32 %10 to i64
  br label %180

154:                                              ; preds = %150
  %155 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %156 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %157 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %158 = sext i32 %9 to i64
  %159 = zext nneg i32 %10 to i64
  %160 = and i64 %159, 1
  %161 = icmp eq i32 %10, 1
  br i1 %161, label %164, label %162

162:                                              ; preds = %154
  %163 = and i64 %159, 2147483646
  br label %184

164:                                              ; preds = %208, %154
  %165 = phi i64 [ 0, %154 ], [ %215, %208 ]
  %166 = phi i64 [ 0, %154 ], [ %213, %208 ]
  %167 = icmp eq i64 %160, 0
  br i1 %167, label %180, label %168

168:                                              ; preds = %164
  %169 = getelementptr inbounds nuw [0 x i64], ptr %155, i64 0, i64 %165
  %170 = load i64, ptr %169, align 8, !tbaa !7
  %171 = icmp slt i64 %165, %158
  br i1 %171, label %172, label %175

172:                                              ; preds = %168
  %173 = getelementptr inbounds nuw [0 x i64], ptr %156, i64 0, i64 %165
  %174 = load i64, ptr %173, align 8, !tbaa !7
  br label %175

175:                                              ; preds = %172, %168
  %176 = phi i64 [ %174, %172 ], [ 0, %168 ]
  %177 = add i64 %176, %166
  %178 = sub i64 %170, %177
  %179 = getelementptr inbounds nuw [0 x i64], ptr %157, i64 0, i64 %165
  store i64 %178, ptr %179, align 8, !tbaa !7
  br label %180

180:                                              ; preds = %175, %164, %152
  %181 = phi i64 [ %153, %152 ], [ %159, %164 ], [ %159, %175 ]
  %182 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %183 = tail call i32 @llvm.smin.i32(i32 %10, i32 0)
  br label %218

184:                                              ; preds = %208, %162
  %185 = phi i64 [ 0, %162 ], [ %215, %208 ]
  %186 = phi i64 [ 0, %162 ], [ %213, %208 ]
  %187 = phi i64 [ 0, %162 ], [ %216, %208 ]
  %188 = getelementptr inbounds nuw [0 x i64], ptr %155, i64 0, i64 %185
  %189 = load i64, ptr %188, align 8, !tbaa !7
  %190 = icmp slt i64 %185, %158
  br i1 %190, label %191, label %194

191:                                              ; preds = %184
  %192 = getelementptr inbounds nuw [0 x i64], ptr %156, i64 0, i64 %185
  %193 = load i64, ptr %192, align 8, !tbaa !7
  br label %194

194:                                              ; preds = %191, %184
  %195 = phi i64 [ %193, %191 ], [ 0, %184 ]
  %196 = add i64 %195, %186
  %197 = sub i64 %189, %196
  %198 = icmp ult i64 %189, %196
  %199 = zext i1 %198 to i64
  %200 = getelementptr inbounds nuw [0 x i64], ptr %157, i64 0, i64 %185
  store i64 %197, ptr %200, align 8, !tbaa !7
  %201 = or disjoint i64 %185, 1
  %202 = getelementptr inbounds nuw [0 x i64], ptr %155, i64 0, i64 %201
  %203 = load i64, ptr %202, align 8, !tbaa !7
  %204 = icmp slt i64 %201, %158
  br i1 %204, label %205, label %208

205:                                              ; preds = %194
  %206 = getelementptr inbounds nuw [0 x i64], ptr %156, i64 0, i64 %201
  %207 = load i64, ptr %206, align 8, !tbaa !7
  br label %208

208:                                              ; preds = %205, %194
  %209 = phi i64 [ %207, %205 ], [ 0, %194 ]
  %210 = add i64 %209, %199
  %211 = sub i64 %203, %210
  %212 = icmp ult i64 %203, %210
  %213 = zext i1 %212 to i64
  %214 = getelementptr inbounds nuw [0 x i64], ptr %157, i64 0, i64 %201
  store i64 %211, ptr %214, align 8, !tbaa !7
  %215 = add nuw nsw i64 %185, 2
  %216 = add i64 %187, 2
  %217 = icmp eq i64 %216, %163
  br i1 %217, label %164, label %184, !llvm.loop !12

218:                                              ; preds = %222, %180
  %219 = phi i64 [ %181, %180 ], [ %223, %222 ]
  %220 = trunc nuw i64 %219 to i32
  %221 = icmp sgt i32 %220, 0
  br i1 %221, label %222, label %227

222:                                              ; preds = %218
  %223 = add nsw i64 %219, -1
  %224 = getelementptr inbounds nuw [0 x i64], ptr %182, i64 0, i64 %223
  %225 = load i64, ptr %224, align 8, !tbaa !7
  %226 = icmp eq i64 %225, 0
  br i1 %226, label %218, label %227, !llvm.loop !13

227:                                              ; preds = %222, %218, %145, %141, %49, %21, %11
  %228 = phi i32 [ %51, %49 ], [ %12, %21 ], [ %12, %11 ], [ %143, %145 ], [ %106, %141 ], [ %220, %222 ], [ %183, %218 ]
  %229 = phi ptr [ %4, %49 ], [ %4, %21 ], [ %4, %11 ], [ %4, %141 ], [ %4, %145 ], [ %6, %218 ], [ %6, %222 ]
  store i32 %228, ptr %0, align 8, !tbaa !3
  %230 = load i32, ptr %229, align 4, !tbaa !3
  %231 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 %230, ptr %231, align 4, !tbaa !3
  %232 = icmp eq i32 %228, 0
  br i1 %232, label %233, label %235

233:                                              ; preds = %227
  %234 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 0, ptr %234, align 4, !tbaa !3
  br label %235

235:                                              ; preds = %233, %227
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @bi_sub(ptr noundef captures(none) %0, ptr noundef readonly captures(none) %1, ptr noundef readonly captures(none) %2) local_unnamed_addr #6 {
  %4 = getelementptr inbounds nuw i8, ptr %2, i64 4
  %5 = load i32, ptr %4, align 4, !tbaa !3
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %7 = load i32, ptr %6, align 4, !tbaa !3
  %8 = icmp eq i32 %7, %5
  %9 = load i32, ptr %1, align 8, !tbaa !3
  %10 = load i32, ptr %2, align 8, !tbaa !3
  br i1 %8, label %55, label %11

11:                                               ; preds = %3
  %12 = tail call i32 @llvm.smax.i32(i32 %9, i32 %10)
  %13 = icmp sgt i32 %12, 0
  br i1 %13, label %14, label %52

14:                                               ; preds = %11
  %15 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %16 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %18 = sext i32 %9 to i64
  %19 = sext i32 %10 to i64
  %20 = zext nneg i32 %12 to i64
  br label %23

21:                                               ; preds = %36
  %22 = icmp eq i64 %46, 0
  br i1 %22, label %52, label %49

23:                                               ; preds = %36, %14
  %24 = phi i64 [ 0, %14 ], [ %47, %36 ]
  %25 = phi i64 [ 0, %14 ], [ %46, %36 ]
  %26 = icmp slt i64 %24, %18
  br i1 %26, label %27, label %30

27:                                               ; preds = %23
  %28 = getelementptr inbounds nuw [0 x i64], ptr %15, i64 0, i64 %24
  %29 = load i64, ptr %28, align 8, !tbaa !7
  br label %30

30:                                               ; preds = %27, %23
  %31 = phi i64 [ %29, %27 ], [ 0, %23 ]
  %32 = icmp slt i64 %24, %19
  br i1 %32, label %33, label %36

33:                                               ; preds = %30
  %34 = getelementptr inbounds nuw [0 x i64], ptr %16, i64 0, i64 %24
  %35 = load i64, ptr %34, align 8, !tbaa !7
  br label %36

36:                                               ; preds = %33, %30
  %37 = phi i64 [ %35, %33 ], [ 0, %30 ]
  %38 = zext i64 %31 to i128
  %39 = zext i64 %37 to i128
  %40 = zext nneg i64 %25 to i128
  %41 = add nuw nsw i128 %38, %40
  %42 = add nuw nsw i128 %41, %39
  %43 = trunc i128 %42 to i64
  %44 = getelementptr inbounds nuw [0 x i64], ptr %17, i64 0, i64 %24
  store i64 %43, ptr %44, align 8, !tbaa !7
  %45 = lshr i128 %42, 64
  %46 = trunc nuw nsw i128 %45 to i64
  %47 = add nuw nsw i64 %24, 1
  %48 = icmp eq i64 %47, %20
  br i1 %48, label %21, label %23, !llvm.loop !9

49:                                               ; preds = %21
  %50 = getelementptr inbounds nuw [0 x i64], ptr %17, i64 0, i64 %20
  store i64 1, ptr %50, align 8, !tbaa !7
  %51 = add nuw nsw i32 %12, 1
  br label %52

52:                                               ; preds = %11, %21, %49
  %53 = phi i32 [ %51, %49 ], [ %12, %21 ], [ %12, %11 ]
  store i32 %53, ptr %0, align 8, !tbaa !3
  %54 = load i32, ptr %6, align 4, !tbaa !3
  br label %237

55:                                               ; preds = %3
  %56 = icmp eq i32 %9, %10
  br i1 %56, label %57, label %61

57:                                               ; preds = %55
  %58 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %59 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %60 = zext i32 %9 to i64
  br label %63

61:                                               ; preds = %55
  %62 = icmp sgt i32 %9, %10
  br i1 %62, label %76, label %156

63:                                               ; preds = %67, %57
  %64 = phi i64 [ %60, %57 ], [ %68, %67 ]
  %65 = trunc nuw i64 %64 to i32
  %66 = icmp slt i32 %65, 1
  br i1 %66, label %76, label %67

67:                                               ; preds = %63
  %68 = add nsw i64 %64, -1
  %69 = getelementptr inbounds nuw [0 x i64], ptr %58, i64 0, i64 %68
  %70 = load i64, ptr %69, align 8, !tbaa !7
  %71 = getelementptr inbounds nuw [0 x i64], ptr %59, i64 0, i64 %68
  %72 = load i64, ptr %71, align 8, !tbaa !7
  %73 = icmp eq i64 %70, %72
  br i1 %73, label %63, label %74, !llvm.loop !11

74:                                               ; preds = %67
  %75 = icmp ugt i64 %70, %72
  br i1 %75, label %76, label %156

76:                                               ; preds = %63, %74, %61
  %77 = icmp sgt i32 %9, 0
  br i1 %77, label %80, label %78

78:                                               ; preds = %76
  %79 = zext i32 %9 to i64
  br label %106

80:                                               ; preds = %76
  %81 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %82 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %83 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %84 = sext i32 %10 to i64
  %85 = zext nneg i32 %9 to i64
  %86 = and i64 %85, 1
  %87 = icmp eq i32 %9, 1
  br i1 %87, label %90, label %88

88:                                               ; preds = %80
  %89 = and i64 %85, 2147483646
  br label %110

90:                                               ; preds = %134, %80
  %91 = phi i64 [ 0, %80 ], [ %141, %134 ]
  %92 = phi i64 [ 0, %80 ], [ %139, %134 ]
  %93 = icmp eq i64 %86, 0
  br i1 %93, label %106, label %94

94:                                               ; preds = %90
  %95 = getelementptr inbounds nuw [0 x i64], ptr %81, i64 0, i64 %91
  %96 = load i64, ptr %95, align 8, !tbaa !7
  %97 = icmp slt i64 %91, %84
  br i1 %97, label %98, label %101

98:                                               ; preds = %94
  %99 = getelementptr inbounds nuw [0 x i64], ptr %82, i64 0, i64 %91
  %100 = load i64, ptr %99, align 8, !tbaa !7
  br label %101

101:                                              ; preds = %98, %94
  %102 = phi i64 [ %100, %98 ], [ 0, %94 ]
  %103 = add i64 %102, %92
  %104 = sub i64 %96, %103
  %105 = getelementptr inbounds nuw [0 x i64], ptr %83, i64 0, i64 %91
  store i64 %104, ptr %105, align 8, !tbaa !7
  br label %106

106:                                              ; preds = %101, %90, %78
  %107 = phi i64 [ %79, %78 ], [ %85, %90 ], [ %85, %101 ]
  %108 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %109 = tail call i32 @llvm.smin.i32(i32 %9, i32 0)
  br label %144

110:                                              ; preds = %134, %88
  %111 = phi i64 [ 0, %88 ], [ %141, %134 ]
  %112 = phi i64 [ 0, %88 ], [ %139, %134 ]
  %113 = phi i64 [ 0, %88 ], [ %142, %134 ]
  %114 = getelementptr inbounds nuw [0 x i64], ptr %81, i64 0, i64 %111
  %115 = load i64, ptr %114, align 8, !tbaa !7
  %116 = icmp slt i64 %111, %84
  br i1 %116, label %117, label %120

117:                                              ; preds = %110
  %118 = getelementptr inbounds nuw [0 x i64], ptr %82, i64 0, i64 %111
  %119 = load i64, ptr %118, align 8, !tbaa !7
  br label %120

120:                                              ; preds = %117, %110
  %121 = phi i64 [ %119, %117 ], [ 0, %110 ]
  %122 = add i64 %121, %112
  %123 = sub i64 %115, %122
  %124 = icmp ult i64 %115, %122
  %125 = zext i1 %124 to i64
  %126 = getelementptr inbounds nuw [0 x i64], ptr %83, i64 0, i64 %111
  store i64 %123, ptr %126, align 8, !tbaa !7
  %127 = or disjoint i64 %111, 1
  %128 = getelementptr inbounds nuw [0 x i64], ptr %81, i64 0, i64 %127
  %129 = load i64, ptr %128, align 8, !tbaa !7
  %130 = icmp slt i64 %127, %84
  br i1 %130, label %131, label %134

131:                                              ; preds = %120
  %132 = getelementptr inbounds nuw [0 x i64], ptr %82, i64 0, i64 %127
  %133 = load i64, ptr %132, align 8, !tbaa !7
  br label %134

134:                                              ; preds = %131, %120
  %135 = phi i64 [ %133, %131 ], [ 0, %120 ]
  %136 = add i64 %135, %125
  %137 = sub i64 %129, %136
  %138 = icmp ult i64 %129, %136
  %139 = zext i1 %138 to i64
  %140 = getelementptr inbounds nuw [0 x i64], ptr %83, i64 0, i64 %127
  store i64 %137, ptr %140, align 8, !tbaa !7
  %141 = add nuw nsw i64 %111, 2
  %142 = add i64 %113, 2
  %143 = icmp eq i64 %142, %89
  br i1 %143, label %90, label %110, !llvm.loop !12

144:                                              ; preds = %148, %106
  %145 = phi i64 [ %107, %106 ], [ %149, %148 ]
  %146 = trunc nuw i64 %145 to i32
  %147 = icmp sgt i32 %146, 0
  br i1 %147, label %148, label %153

148:                                              ; preds = %144
  %149 = add nsw i64 %145, -1
  %150 = getelementptr inbounds nuw [0 x i64], ptr %108, i64 0, i64 %149
  %151 = load i64, ptr %150, align 8, !tbaa !7
  %152 = icmp eq i64 %151, 0
  br i1 %152, label %144, label %153, !llvm.loop !13

153:                                              ; preds = %144, %148
  %154 = phi i32 [ %109, %144 ], [ %146, %148 ]
  store i32 %154, ptr %0, align 8, !tbaa !3
  %155 = load i32, ptr %6, align 4, !tbaa !3
  br label %237

156:                                              ; preds = %61, %74
  %157 = icmp sgt i32 %10, 0
  br i1 %157, label %160, label %158

158:                                              ; preds = %156
  %159 = zext i32 %10 to i64
  br label %186

160:                                              ; preds = %156
  %161 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %162 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %163 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %164 = sext i32 %9 to i64
  %165 = zext nneg i32 %10 to i64
  %166 = and i64 %165, 1
  %167 = icmp eq i32 %10, 1
  br i1 %167, label %170, label %168

168:                                              ; preds = %160
  %169 = and i64 %165, 2147483646
  br label %190

170:                                              ; preds = %214, %160
  %171 = phi i64 [ 0, %160 ], [ %221, %214 ]
  %172 = phi i64 [ 0, %160 ], [ %219, %214 ]
  %173 = icmp eq i64 %166, 0
  br i1 %173, label %186, label %174

174:                                              ; preds = %170
  %175 = getelementptr inbounds nuw [0 x i64], ptr %161, i64 0, i64 %171
  %176 = load i64, ptr %175, align 8, !tbaa !7
  %177 = icmp slt i64 %171, %164
  br i1 %177, label %178, label %181

178:                                              ; preds = %174
  %179 = getelementptr inbounds nuw [0 x i64], ptr %162, i64 0, i64 %171
  %180 = load i64, ptr %179, align 8, !tbaa !7
  br label %181

181:                                              ; preds = %178, %174
  %182 = phi i64 [ %180, %178 ], [ 0, %174 ]
  %183 = add i64 %182, %172
  %184 = sub i64 %176, %183
  %185 = getelementptr inbounds nuw [0 x i64], ptr %163, i64 0, i64 %171
  store i64 %184, ptr %185, align 8, !tbaa !7
  br label %186

186:                                              ; preds = %181, %170, %158
  %187 = phi i64 [ %159, %158 ], [ %165, %170 ], [ %165, %181 ]
  %188 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %189 = tail call i32 @llvm.smin.i32(i32 %10, i32 0)
  br label %224

190:                                              ; preds = %214, %168
  %191 = phi i64 [ 0, %168 ], [ %221, %214 ]
  %192 = phi i64 [ 0, %168 ], [ %219, %214 ]
  %193 = phi i64 [ 0, %168 ], [ %222, %214 ]
  %194 = getelementptr inbounds nuw [0 x i64], ptr %161, i64 0, i64 %191
  %195 = load i64, ptr %194, align 8, !tbaa !7
  %196 = icmp slt i64 %191, %164
  br i1 %196, label %197, label %200

197:                                              ; preds = %190
  %198 = getelementptr inbounds nuw [0 x i64], ptr %162, i64 0, i64 %191
  %199 = load i64, ptr %198, align 8, !tbaa !7
  br label %200

200:                                              ; preds = %197, %190
  %201 = phi i64 [ %199, %197 ], [ 0, %190 ]
  %202 = add i64 %201, %192
  %203 = sub i64 %195, %202
  %204 = icmp ult i64 %195, %202
  %205 = zext i1 %204 to i64
  %206 = getelementptr inbounds nuw [0 x i64], ptr %163, i64 0, i64 %191
  store i64 %203, ptr %206, align 8, !tbaa !7
  %207 = or disjoint i64 %191, 1
  %208 = getelementptr inbounds nuw [0 x i64], ptr %161, i64 0, i64 %207
  %209 = load i64, ptr %208, align 8, !tbaa !7
  %210 = icmp slt i64 %207, %164
  br i1 %210, label %211, label %214

211:                                              ; preds = %200
  %212 = getelementptr inbounds nuw [0 x i64], ptr %162, i64 0, i64 %207
  %213 = load i64, ptr %212, align 8, !tbaa !7
  br label %214

214:                                              ; preds = %211, %200
  %215 = phi i64 [ %213, %211 ], [ 0, %200 ]
  %216 = add i64 %215, %205
  %217 = sub i64 %209, %216
  %218 = icmp ult i64 %209, %216
  %219 = zext i1 %218 to i64
  %220 = getelementptr inbounds nuw [0 x i64], ptr %163, i64 0, i64 %207
  store i64 %217, ptr %220, align 8, !tbaa !7
  %221 = add nuw nsw i64 %191, 2
  %222 = add i64 %193, 2
  %223 = icmp eq i64 %222, %169
  br i1 %223, label %170, label %190, !llvm.loop !12

224:                                              ; preds = %228, %186
  %225 = phi i64 [ %187, %186 ], [ %229, %228 ]
  %226 = trunc nuw i64 %225 to i32
  %227 = icmp sgt i32 %226, 0
  br i1 %227, label %228, label %233

228:                                              ; preds = %224
  %229 = add nsw i64 %225, -1
  %230 = getelementptr inbounds nuw [0 x i64], ptr %188, i64 0, i64 %229
  %231 = load i64, ptr %230, align 8, !tbaa !7
  %232 = icmp eq i64 %231, 0
  br i1 %232, label %224, label %233, !llvm.loop !13

233:                                              ; preds = %224, %228
  %234 = phi i32 [ %189, %224 ], [ %226, %228 ]
  store i32 %234, ptr %0, align 8, !tbaa !3
  %235 = load i32, ptr %6, align 4, !tbaa !3
  %236 = xor i32 %235, 1
  br label %237

237:                                              ; preds = %153, %233, %52
  %238 = phi i32 [ %155, %153 ], [ %236, %233 ], [ %54, %52 ]
  %239 = phi i32 [ %154, %153 ], [ %234, %233 ], [ %53, %52 ]
  %240 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 %238, ptr %240, align 4, !tbaa !3
  %241 = icmp eq i32 %239, 0
  br i1 %241, label %242, label %244

242:                                              ; preds = %237
  %243 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 0, ptr %243, align 4, !tbaa !3
  br label %244

244:                                              ; preds = %242, %237
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite) uwtable
define dso_local void @bi_neg(ptr noundef writeonly captures(none) initializes((0, 8)) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #2 {
  %3 = load i32, ptr %1, align 8, !tbaa !3
  store i32 %3, ptr %0, align 8, !tbaa !3
  %4 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %5 = load i32, ptr %4, align 4, !tbaa !3
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 %5, ptr %6, align 4, !tbaa !3
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %8 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %9 = load i32, ptr %1, align 8, !tbaa !3
  %10 = sext i32 %9 to i64
  %11 = shl nsw i64 %10, 3
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %7, ptr nonnull readonly align 8 %8, i64 %11, i1 false)
  %12 = icmp sgt i32 %3, 0
  br i1 %12, label %13, label %15

13:                                               ; preds = %2
  %14 = xor i32 %5, 1
  store i32 %14, ptr %6, align 4, !tbaa !3
  br label %15

15:                                               ; preds = %13, %2
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local range(i32 0, 2) i32 @bi_is_zero(ptr noundef readonly captures(none) %0) local_unnamed_addr #4 {
  %2 = load i32, ptr %0, align 8, !tbaa !3
  %3 = icmp eq i32 %2, 0
  %4 = zext i1 %3 to i32
  ret i32 %4
}

; Function Attrs: mustprogress nofree nounwind uwtable
define dso_local void @bi_print(ptr noundef readonly captures(none) %0) local_unnamed_addr #7 {
  %2 = alloca [256 x i64], align 16
  %3 = alloca [1024 x i8], align 16
  %4 = load i32, ptr %0, align 8, !tbaa !3
  %5 = icmp eq i32 %4, 0
  br i1 %5, label %6, label %11

6:                                                ; preds = %1
  %7 = load ptr, ptr @stdout, align 8, !tbaa !14
  %8 = tail call i32 @putc(i32 noundef 48, ptr noundef %7)
  %9 = load ptr, ptr @stdout, align 8, !tbaa !14
  %10 = tail call i32 @putc(i32 noundef 10, ptr noundef %9)
  br label %78

11:                                               ; preds = %1
  call void @llvm.lifetime.start.p0(i64 2048, ptr nonnull %2) #13
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %13 = sext i32 %4 to i64
  %14 = shl nsw i64 %13, 3
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 16 %2, ptr nonnull align 8 %12, i64 %14, i1 false)
  call void @llvm.lifetime.start.p0(i64 1024, ptr nonnull %3) #13
  %15 = icmp sgt i32 %4, 0
  br i1 %15, label %16, label %54

16:                                               ; preds = %11, %51
  %17 = phi i64 [ %23, %51 ], [ 0, %11 ]
  %18 = phi i32 [ %44, %51 ], [ %4, %11 ]
  %19 = zext nneg i32 %18 to i64
  br label %25

20:                                               ; preds = %25
  %21 = trunc nuw nsw i128 %39 to i8
  %22 = or disjoint i8 %21, 48
  %23 = add nuw nsw i64 %17, 1
  %24 = getelementptr inbounds nuw [1024 x i8], ptr %3, i64 0, i64 %17
  store i8 %22, ptr %24, align 1, !tbaa !17
  br label %42

25:                                               ; preds = %16, %25
  %26 = phi i64 [ %19, %16 ], [ %28, %25 ]
  %27 = phi i128 [ 0, %16 ], [ %39, %25 ]
  %28 = add nsw i64 %26, -1
  %29 = shl nuw nsw i128 %27, 64
  %30 = and i64 %28, 4294967295
  %31 = getelementptr inbounds nuw [256 x i64], ptr %2, i64 0, i64 %30
  %32 = load i64, ptr %31, align 8, !tbaa !7
  %33 = zext i64 %32 to i128
  %34 = or disjoint i128 %29, %33
  %35 = freeze i128 %34
  %36 = udiv i128 %35, 10
  %37 = trunc nuw i128 %36 to i64
  store i64 %37, ptr %31, align 8, !tbaa !7
  %38 = mul i128 %36, 10
  %39 = sub i128 %35, %38
  %40 = trunc nuw i64 %26 to i32
  %41 = icmp sgt i32 %40, 1
  br i1 %41, label %25, label %20, !llvm.loop !18

42:                                               ; preds = %46, %20
  %43 = phi i64 [ %47, %46 ], [ %19, %20 ]
  %44 = trunc nuw i64 %43 to i32
  %45 = icmp sgt i32 %44, 0
  br i1 %45, label %46, label %52

46:                                               ; preds = %42
  %47 = add nsw i64 %43, -1
  %48 = getelementptr inbounds nuw [256 x i64], ptr %2, i64 0, i64 %47
  %49 = load i64, ptr %48, align 8, !tbaa !7
  %50 = icmp eq i64 %49, 0
  br i1 %50, label %42, label %51, !llvm.loop !19

51:                                               ; preds = %46
  br label %16, !llvm.loop !20

52:                                               ; preds = %42
  %53 = trunc nuw i64 %23 to i32
  br label %54

54:                                               ; preds = %52, %11
  %55 = phi i32 [ 0, %11 ], [ %53, %52 ]
  %56 = getelementptr inbounds nuw i8, ptr %0, i64 4
  %57 = load i32, ptr %56, align 4, !tbaa !3
  %58 = icmp eq i32 %57, 0
  br i1 %58, label %62, label %59

59:                                               ; preds = %54
  %60 = load ptr, ptr @stdout, align 8, !tbaa !14
  %61 = tail call i32 @putc(i32 noundef 45, ptr noundef %60)
  br label %62

62:                                               ; preds = %59, %54
  %63 = icmp sgt i32 %55, 0
  br i1 %63, label %64, label %75

64:                                               ; preds = %62
  %65 = zext nneg i32 %55 to i64
  br label %66

66:                                               ; preds = %64, %66
  %67 = phi i64 [ %65, %64 ], [ %68, %66 ]
  %68 = add nsw i64 %67, -1
  %69 = getelementptr inbounds nuw [1024 x i8], ptr %3, i64 0, i64 %68
  %70 = load i8, ptr %69, align 1, !tbaa !17
  %71 = sext i8 %70 to i32
  %72 = load ptr, ptr @stdout, align 8, !tbaa !14
  %73 = tail call i32 @putc(i32 noundef %71, ptr noundef %72)
  %74 = icmp samesign ugt i64 %67, 1
  br i1 %74, label %66, label %75, !llvm.loop !21

75:                                               ; preds = %66, %62
  %76 = load ptr, ptr @stdout, align 8, !tbaa !14
  %77 = tail call i32 @putc(i32 noundef 10, ptr noundef %76)
  call void @llvm.lifetime.end.p0(i64 1024, ptr nonnull %3) #13
  call void @llvm.lifetime.end.p0(i64 2048, ptr nonnull %2) #13
  br label %78

78:                                               ; preds = %75, %6
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @bi_from_str(ptr noundef captures(none) initializes((0, 8)) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #6 {
  store i32 0, ptr %0, align 8, !tbaa !3
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 4
  store i32 0, ptr %3, align 4, !tbaa !3
  %4 = load i8, ptr %1, align 1, !tbaa !17
  switch i8 %4, label %9 [
    i8 45, label %5
    i8 43, label %6
  ]

5:                                                ; preds = %2
  store i32 1, ptr %3, align 4, !tbaa !3
  br label %6

6:                                                ; preds = %2, %5
  %7 = getelementptr inbounds nuw i8, ptr %1, i64 1
  %8 = load i8, ptr %7, align 1, !tbaa !17
  br label %9

9:                                                ; preds = %6, %2
  %10 = phi i8 [ %8, %6 ], [ %4, %2 ]
  %11 = phi ptr [ %7, %6 ], [ %1, %2 ]
  %12 = icmp eq i8 %10, 0
  br i1 %12, label %81, label %13

13:                                               ; preds = %9
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 8
  br label %15

15:                                               ; preds = %13, %75
  %16 = phi i32 [ 0, %13 ], [ %76, %75 ]
  %17 = phi i8 [ %10, %13 ], [ %77, %75 ]
  %18 = phi ptr [ %11, %13 ], [ %19, %75 ]
  %19 = getelementptr inbounds nuw i8, ptr %18, i64 1
  %20 = sext i8 %17 to i64
  %21 = add nsw i64 %20, -48
  %22 = icmp sgt i32 %16, 0
  br i1 %22, label %23, label %44

23:                                               ; preds = %15
  %24 = zext nneg i32 %16 to i64
  %25 = and i64 %24, 1
  %26 = icmp eq i32 %16, 1
  br i1 %26, label %29, label %27

27:                                               ; preds = %23
  %28 = and i64 %24, 2147483646
  br label %47

29:                                               ; preds = %47, %23
  %30 = phi i64 [ poison, %23 ], [ %67, %47 ]
  %31 = phi i64 [ 0, %23 ], [ %68, %47 ]
  %32 = phi i64 [ %21, %23 ], [ %67, %47 ]
  %33 = icmp eq i64 %25, 0
  br i1 %33, label %44, label %34

34:                                               ; preds = %29
  %35 = getelementptr inbounds nuw [0 x i64], ptr %14, i64 0, i64 %31
  %36 = load i64, ptr %35, align 8, !tbaa !7
  %37 = zext i64 %36 to i128
  %38 = mul nuw nsw i128 %37, 10
  %39 = zext i64 %32 to i128
  %40 = add nuw nsw i128 %38, %39
  %41 = trunc i128 %40 to i64
  store i64 %41, ptr %35, align 8, !tbaa !7
  %42 = lshr i128 %40, 64
  %43 = trunc nuw nsw i128 %42 to i64
  br label %44

44:                                               ; preds = %34, %29, %15
  %45 = phi i64 [ %21, %15 ], [ %30, %29 ], [ %43, %34 ]
  %46 = icmp eq i64 %45, 0
  br i1 %46, label %75, label %71

47:                                               ; preds = %47, %27
  %48 = phi i64 [ 0, %27 ], [ %68, %47 ]
  %49 = phi i64 [ %21, %27 ], [ %67, %47 ]
  %50 = phi i64 [ 0, %27 ], [ %69, %47 ]
  %51 = getelementptr inbounds nuw [0 x i64], ptr %14, i64 0, i64 %48
  %52 = load i64, ptr %51, align 8, !tbaa !7
  %53 = zext i64 %52 to i128
  %54 = mul nuw nsw i128 %53, 10
  %55 = zext i64 %49 to i128
  %56 = add nuw nsw i128 %54, %55
  %57 = trunc i128 %56 to i64
  store i64 %57, ptr %51, align 8, !tbaa !7
  %58 = lshr i128 %56, 64
  %59 = or disjoint i64 %48, 1
  %60 = getelementptr inbounds nuw [0 x i64], ptr %14, i64 0, i64 %59
  %61 = load i64, ptr %60, align 8, !tbaa !7
  %62 = zext i64 %61 to i128
  %63 = mul nuw nsw i128 %62, 10
  %64 = add nuw nsw i128 %63, %58
  %65 = trunc i128 %64 to i64
  store i64 %65, ptr %60, align 8, !tbaa !7
  %66 = lshr i128 %64, 64
  %67 = trunc nuw nsw i128 %66 to i64
  %68 = add nuw nsw i64 %48, 2
  %69 = add i64 %50, 2
  %70 = icmp eq i64 %69, %28
  br i1 %70, label %29, label %47, !llvm.loop !22

71:                                               ; preds = %44
  %72 = add nsw i32 %16, 1
  store i32 %72, ptr %0, align 8, !tbaa !3
  %73 = sext i32 %16 to i64
  %74 = getelementptr inbounds [0 x i64], ptr %14, i64 0, i64 %73
  store i64 %45, ptr %74, align 8, !tbaa !7
  br label %75

75:                                               ; preds = %71, %44
  %76 = phi i32 [ %72, %71 ], [ %16, %44 ]
  %77 = load i8, ptr %19, align 1, !tbaa !17
  %78 = icmp eq i8 %77, 0
  br i1 %78, label %79, label %15, !llvm.loop !23

79:                                               ; preds = %75
  %80 = icmp eq i32 %76, 0
  br i1 %80, label %81, label %82

81:                                               ; preds = %9, %79
  store i32 0, ptr %3, align 4, !tbaa !3
  br label %82

82:                                               ; preds = %81, %79
  ret void
}

; Function Attrs: mustprogress nofree norecurse nounwind willreturn memory(argmem: read) uwtable
define dso_local range(i32 -33554430, 33554433) i32 @bi_str_size(ptr noundef readonly captures(none) %0) local_unnamed_addr #8 {
  %2 = load i8, ptr %0, align 1, !tbaa !17
  switch i8 %2, label %5 [
    i8 45, label %3
    i8 43, label %3
  ]

3:                                                ; preds = %1, %1
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 1
  br label %5

5:                                                ; preds = %1, %3
  %6 = phi ptr [ %4, %3 ], [ %0, %1 ]
  %7 = tail call i64 @strlen(ptr noundef nonnull dereferenceable(1) %6) #14
  %8 = trunc i64 %7 to i32
  %9 = shl nsw i32 %8, 2
  %10 = add nsw i32 %9, 63
  %11 = sdiv i32 %10, 64
  %12 = add nsw i32 %11, 1
  ret i32 %12
}

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: read)
declare dso_local i64 @strlen(ptr noundef captures(none)) local_unnamed_addr #9

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none) uwtable
define dso_local range(i32 8, 1) i32 @bi_buf_size(i32 noundef %0) local_unnamed_addr #10 {
  %2 = shl i32 %0, 3
  %3 = add i32 %2, 8
  ret i32 %3
}

; Function Attrs: nofree nounwind
declare dso_local noundef i32 @putc(i32 noundef, ptr noundef captures(none)) local_unnamed_addr #11

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.abs.i64(i64, i1 immarg) #12

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.smax.i32(i32, i32) #12

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.smin.i32(i32, i32) #12

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: write) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #2 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #3 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #4 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #5 = { mustprogress nofree norecurse nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #6 = { mustprogress nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #7 = { mustprogress nofree nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #8 = { mustprogress nofree norecurse nounwind willreturn memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #9 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: read) "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #10 = { mustprogress nofree norecurse nosync nounwind willreturn memory(none) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #11 = { nofree nounwind "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #12 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #13 = { nounwind }
attributes #14 = { nounwind willreturn memory(read) }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"uwtable", i32 2}
!2 = !{!"clang version 21.1.7 (Fedora 21.1.7-1.fc44)"}
!3 = !{!4, !4, i64 0}
!4 = !{!"int", !5, i64 0}
!5 = !{!"omnipotent char", !6, i64 0}
!6 = !{!"Simple C++ TBAA"}
!7 = !{!8, !8, i64 0}
!8 = !{!"long", !5, i64 0}
!9 = distinct !{!9, !10}
!10 = !{!"llvm.loop.mustprogress"}
!11 = distinct !{!11, !10}
!12 = distinct !{!12, !10}
!13 = distinct !{!13, !10}
!14 = !{!15, !15, i64 0}
!15 = !{!"p1 _ZTS8_IO_FILE", !16, i64 0}
!16 = !{!"any pointer", !5, i64 0}
!17 = !{!5, !5, i64 0}
!18 = distinct !{!18, !10}
!19 = distinct !{!19, !10}
!20 = distinct !{!20, !10}
!21 = distinct !{!21, !10}
!22 = distinct !{!22, !10}
!23 = distinct !{!23, !10}

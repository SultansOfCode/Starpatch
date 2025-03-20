cls
zig build

del resources\smaller2bigger_patch.sp 2>NUL
del resources\smaller2bigger_patched.txt 2>NUL

zig-out\bin\Starpatch.exe create resources\smaller.txt resources\bigger.txt resources\smaller2bigger_patch.sp
zig-out\bin\Starpatch.exe patch resources\smaller.txt resources\smaller2bigger_patch.sp resources\smaller2bigger_patched.txt

@del resources\bigger2smaller_patch.sp 2>NUL
@del resources\bigger2smaller_patched.txt 2>NUL

zig-out\bin\Starpatch.exe create resources\bigger.txt resources\smaller.txt resources\bigger2smaller_patch.sp
zig-out\bin\Starpatch.exe patch resources\bigger.txt resources\bigger2smaller_patch.sp resources\bigger2smaller_patched.txt

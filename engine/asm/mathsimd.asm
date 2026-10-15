; ============================================================================
; mathsimd.asm — SIMD-ускоренное ядро 3D-движка (NASM, x86-64)
;   * mat4_transform_simd : матрица 4x4 * массив vec4 (SSE)
;   * sw_rasterize        : растеризатор треугольника (flat + src-over blend)
; ABI: System V AMD64 (Linux / elf64) по умолчанию;
;      Microsoft x64 (MinGW-w64 / win64) при nasm -D ENGINE_WIN64_ASM.
; ============================================================================

DEFAULT REL

; ---------------------------------------------------------------------------
; void mat4_transform_simd(const float* m, const float* verts,
;                          float* out, int count)
global mat4_transform_simd
%ifdef ENGINE_WIN64_ASM
  %define MT_M rcx
  %define MT_V rdx
  %define MT_O r8
  %define MT_N r9d
%else
  %define MT_M rdi
  %define MT_V rsi
  %define MT_O rdx
  %define MT_N ecx
%endif

section .text align=16
mat4_transform_simd:
    movups xmm4, [MT_M]                 ; col0
    movups xmm5, [MT_M + 16]            ; col1
    movups xmm6, [MT_M + 32]            ; col2
    movups xmm7, [MT_M + 48]            ; col3

    test MT_N, MT_N
    jle .mtdone
    xor eax, eax                        ; байтовое смещение

.mtloop:
    movups xmm0, [MT_V + rax]           ; v = {x,y,z,w}
    ; splat-векторы из xmm0 в xmm8..xmm11 (xmm0 остаётся нетронутым)
    movaps xmm8, xmm0
    shufps xmm8, xmm8, 0x00             ; xxxx
    movaps xmm9, xmm0
    shufps xmm9, xmm9, 0x55             ; yyyy
    movaps xmm10, xmm0
    shufps xmm10, xmm10, 0xAA           ; zzzz
    movaps xmm11, xmm0
    shufps xmm11, xmm11, 0xFF           ; wwww
    ; acc = col0*x + col1*y + col2*z + col3*w
    movaps xmm1, xmm4
    mulps  xmm1, xmm8
    movaps xmm2, xmm5
    mulps  xmm2, xmm9
    addps  xmm1, xmm2
    movaps xmm2, xmm6
    mulps  xmm2, xmm10
    addps  xmm1, xmm2
    mulps  xmm7, xmm11
    addps  xmm1, xmm7
    movups [MT_O + rax], xmm1

    add rax, 16
    dec MT_N
    jnz .mtloop
.mtdone:
    ret

; ---------------------------------------------------------------------------
; void sw_rasterize(const int32_t* screenTri, // x0,y0,x1,y1,x2,y2
;                   const float* invArea,      // {1/A,1/A}; ориентация нормализована
;                                              // на C++ стороне (внутри e_i >= 0)
;                   const float* color,        // RGBA 0..1
;                   uint8_t* fb,               // BGRA8, rowStride = fbW*4
;                   int fbW, int fbH)
; Регистры основного цикла:
;   rbx = указатель текущего пикселя
;   rbp = y текущей строки
;   r12/r13/r14 = текущие e0/e1/e2 (курсоры строки в памяти между строками)
;   r15 = конец строки (exclusive ptr)
; GPR caller-saved для тела пикселя: rax, rcx, rdx, rsi, rdi, r8-r11.
global sw_rasterize
%ifdef ENGINE_WIN64_ASM
  %define RT_TRI rcx
  %define RT_IA  rdx
  %define RT_COL r8
  %define RT_FB  r9
%else
  %define RT_TRI rdi
  %define RT_IA  rsi
  %define RT_COL rdx
  %define RT_FB  rcx
%endif

; карта фрейма (смещения от FR):
%define F_FB     0      ; fb base
%define F_RS     8      ; rowStride = fbW*4
%define F_MINX   16
%define F_MAXX   24     ; exclusive
%define F_MAXY   32     ; exclusive
%define F_DXE0   40
%define F_DXE1   48
%define F_DXE2   56
%define F_DYE0   64
%define F_DYE1   72
%define F_DYE2   80
%define F_E0ST   88     ; курсор e0 (обновляется по строкам)
%define F_E1ST   96
%define F_E2ST   104
%define F_SRCBG  112    ; B8 | G8<<8 | R8<<16
%define F_SRCA   120    ; A8 (0..255)
%define F_TRI    128    ; tri ptr (для перечитывания вершин)
%define F_COL    136    ; col ptr (сохраняется на время bbox)
%define F_SIZE   144

sw_rasterize:
%ifdef ENGINE_WIN64_ASM
    mov r10d, [rsp + 48]                ; fbW (5-й параметр MS x64)
    mov r11d, [rsp + 56]                ; fbH (6-й параметр)
%else
    mov r10d, r8d                       ; SysV: fbW=r8d, fbH=r9d
    mov r11d, r9d
%endif
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15                            ; rsp % 16 == 8 (обе ABI)
    sub  rsp, F_SIZE + 16               ; выравнивание: (rsp+16) % 16 == 0
    %define FR (rsp + 16)

    mov [FR + F_FB],  RT_FB
    mov [FR + F_TRI], RT_TRI            ; фиксируем tri/col ptr ДО любых порч
    mov [FR + F_COL], RT_COL
    movsxd r12, r10d                    ; fbW
    lea r13, [r12 * 4]
    mov [FR + F_RS], r13                ; rowStride
    mov [FR + F_MAXY], r11              ; временно: fbH (для clamp maxY)

    ; ======================= bbox =======================
    mov rdi, [FR + F_TRI]               ; tri ptr из стека в постоянный временный rdi
    movsx eax,  dword [rdi + 0]          ; x0
    movsx ecx,  dword [rdi + 4]          ; y0
    movsx r10d, dword [rdi + 8]          ; x1
    movsx r11d, dword [rdi + 12]         ; y1
    movsx r12d, dword [rdi + 16]         ; x2
    movsx r14d, dword [rdi + 20]         ; y2

    ; minX -> rbx
    mov rbx, rax
    cmp rbx, r10
    cmovg rbx, r10
    cmp rbx, r12
    cmovg rbx, r12
    cmp rbx, 0
    cmovl rbx, qword [rel .zero_q]
    mov [FR + F_MINX], rbx
    ; maxX+1 -> rbx (fbW восстановим из rowStride; НЕ трогаем r9=RT_FB!)
    mov rbx, rax
    cmp rbx, r10
    cmovl rbx, r10
    cmp rbx, r12
    cmovl rbx, r12
    inc rbx
    mov r15, [FR + F_RS]
    shr r15, 2                          ; fbW
    cmp rbx, r15
    cmovg rbx, r15
    mov [FR + F_MAXX], rbx
    mov [FR + F_FB], RT_FB              ; единая точка: фиксируем fb base до порчи r9/r8
    ; minY -> rbp
    mov rbp, rcx
    cmp rbp, r11
    cmovg rbp, r11
    cmp rbp, r14
    cmovg rbp, r14
    cmp rbp, 0
    cmovl rbp, qword [rel .zero_q]
    ; maxY+1 -> rbx (fbH читаем из слота)
    mov rbx, rcx
    cmp rbx, r11
    cmovl rbx, r11
    cmp rbx, r14
    cmovl rbx, r14
    inc rbx
    mov r15, [FR + F_MAXY]              ; fbH
    cmp rbx, r15
    cmovg rbx, r15
    mov [FR + F_MAXY], rbx              ; теперь это maxY+1

    ; пустой bbox?
    mov rbx, [FR + F_MINX]
    mov r15, [FR + F_MAXX]
    cmp rbx, r15
    jae .rt_finish
    cmp rbp, [FR + F_MAXY]
    jae .rt_finish

    ; ======================= edge coefficients =======================
    ; dxe = By-Ay, dye = Ax-Bx для рёбер v0->v1, v1->v2, v2->v0
    ; (rax=x0, rcx=y0, r10=x1, r11=y1 живы)
    mov r15d, r11d
    sub r15d, ecx
    movsxd r15, r15d
    mov [FR + F_DXE0], r15              ; dxe0 = y1-y0
    mov r12d, eax
    sub r12d, r10d
    movsxd r12, r12d
    mov [FR + F_DYE0], r12              ; dye0 = x0-x1

    movsx r13d, dword [rdi + 16]     ; x2
    movsx r14d, dword [rdi + 20]     ; y2
    mov r15d, r14d
    sub r15d, r11d
    movsxd r15, r15d
    mov [FR + F_DXE1], r15              ; dxe1 = y2-y1
    mov r12d, r10d
    sub r12d, r13d
    movsxd r12, r12d
    mov [FR + F_DYE1], r12              ; dye1 = x1-x2

    mov r15d, ecx
    sub r15d, r14d
    movsxd r15, r15d
    mov [FR + F_DXE2], r15              ; dxe2 = y0-y2
    mov r12d, r13d
    sub r12d, eax
    movsxd r12, r12d
    mov [FR + F_DYE2], r12              ; dye2 = x2-x0

    ; ======================= e_i в (minX, minY) =======================
    mov rbx, [FR + F_MINX]
    ; e0 = dxe0*(minX-x0) + dye0*(minY-y0)
    mov r15, rbx
    sub r15, rax
    imul r15, [FR + F_DXE0]
    mov r12, rbp
    sub r12, rcx
    imul r12, [FR + F_DYE0]
    add r15, r12
    mov [FR + F_E0ST], r15
    ; e1 = dxe1*(minX-x1) + dye1*(minY-y1)
    mov r15, rbx
    sub r15, r10
    imul r15, [FR + F_DXE1]
    mov r12, rbp
    sub r12, r11
    imul r12, [FR + F_DYE1]
    add r15, r12
    mov [FR + F_E1ST], r15
    ; e2 = dxe2*(minX-x2) + dye2*(minY-y2)
    mov r15, rbx
    sub r15, r13
    imul r15, [FR + F_DXE2]
    mov r12, rbp
    sub r12, r14
    imul r12, [FR + F_DYE2]
    add r15, r12
    mov [FR + F_E2ST], r15

    ; ======================= цвет -> fixed point =======================
    mov r15, [FR + F_COL]
    movss xmm0, [r15 + 0]               ; R
    movss xmm1, [r15 + 4]               ; G
    movss xmm2, [r15 + 8]               ; B
    movss xmm3, [r15 + 12]              ; A
    mov eax, 255
    cvtsi2ss xmm7, eax
    mulss xmm0, xmm7
    mulss xmm1, xmm7
    mulss xmm2, xmm7
    mulss xmm3, xmm7
    cvtss2si eax, xmm0                  ; R8
    cvtss2si ecx, xmm1                  ; G8
    cvtss2si r10d, xmm2                 ; B8
    cvtss2si r11d, xmm3                 ; A8
    ; clamp(0,255) — без ветвлений, cmov (корректно для любого GPR32)
%macro CLAMPB 1                         ; reg32
    xor r9d, r9d
    test %1, %1
    cmovl %1, r9d                       ; если < 0 -> 0
    mov r9d, 255
    cmp %1, r9d
    cmovg %1, r9d                       ; если > 255 -> 255
%endmacro
    CLAMPB eax
    CLAMPB ecx
    CLAMPB r10d
    CLAMPB r11d
    ; упаковка: F_SRCBG = B8 | G8<<8 | R8<<16 ; F_SRCA = A8
    movzx r10d, r10b                    ; B8
    movzx r11d, r11b                    ; A8
    movzx ecx, cl                       ; G8
    movzx eax, al                       ; R8
    shl ecx, 8
    or ecx, r10d                        ; B|G<<8
    shl eax, 16
    or ecx, eax                         ; B|G<<8|R<<16
    mov [FR + F_SRCBG], rcx
    mov [FR + F_SRCA], r11

    ; ======================= основной цикл =======================
.row_load:
    mov r12, [FR + F_E0ST]              ; курсоры e на начало строки
    mov r13, [FR + F_E1ST]
    mov r14, [FR + F_E2ST]
    ; rbx = fb + y*rowStride + minX*4
    mov rbx, [FR + F_FB]
    mov rax, rbp
    imul rax, [FR + F_RS]
    add rbx, rax
    mov rax, [FR + F_MINX]
    shl rax, 2
    add rbx, rax
    ; r15 = rbx + (maxX-minX)*4
    mov r15, rbx
    mov rax, [FR + F_MAXX]
    sub rax, [FR + F_MINX]
    shl rax, 2
    add r15, rax

.col_start:
    cmp rbx, r15
    jae .row_end

    ; тест покрытия: e0,e1,e2 >= 0 ?
    test r12, r12
    js .col_skip
    test r13, r13
    js .col_skip
    test r14, r14
    js .col_skip

    ; ---- src-over blend по каналам: out_c = (src_c*a + dst_c*(256-a)) >> 8 ----
    ; dst BGRA в eax; src B|G<<8|R<<16 в [F_SRCBG]; a в [F_SRCA].
    ; Регистры: rax(dst->итог), rcx(a), rdx(na), r8(srcB), r9(srcG), r10(srcR),
    ;           r11(промежуточное), rsi/rdi(скаловы). rbx/rbp/r12-r15 заняты циклом.
    mov eax, [rbx]                      ; dst BGRA
    movzx r8d, al                       ; dstB
    mov r9d, eax
    shr r9d, 8
    movzx r9d, r9b                      ; dstG
    mov edx, eax
    shr edx, 16
    movzx r10d, dl                      ; dstR
    shr eax, 24                         ; dstA (не используем — непрозрачный fb)

    movzx ecx, byte [FR + F_SRCA]       ; a
    mov edx, 256
    sub edx, ecx                        ; na = 256-a

    ; src каналы
    movzx r11d, byte [FR + F_SRCBG]     ; srcB  (r11 освободился после dstA)
    ; B: res = (srcB*a + dstB*na) >> 8
    imul r11d, ecx
    imul r8d, edx
    add r11d, r8d
    shr r11d, 8                         ; resB -> r11
    ; G
    movzx r8d, byte [FR + F_SRCBG + 1]  ; srcG
    imul r8d, ecx
    imul r9d, edx
    add r8d, r9d
    shr r8d, 8                          ; resG -> r8
    ; R
    movzx r9d, byte [FR + F_SRCBG + 2]  ; srcR
    imul r9d, ecx
    imul r10d, edx
    add r9d, r10d
    shr r9d, 8                          ; resR -> r9
    ; A: src-over alpha: aOut = a + dstA*(256-a)>>8 (dst обычно opaque)
    movzx r10d, byte [FR + F_SRCA]      ; a ещё раз
    imul r10d, 256                      ; -> a*256 ~ максимальный выход
    cmp r10d, 65535
    jbe .a_ok
    mov r10d, 65535
.a_ok:
    shr r10d, 8                         ; resA ~ a (для opaque dst)
    ; упаковка BGRA обратно в eax и запись
    shl r8d, 8                          ; resG<<8
    or  r11d, r8d                       ; resB | resG<<8
    shl r9d, 16                         ; resR<<16
    or  r11d, r9d
    shl r10d, 24                        ; resA<<24
    or  r11d, r10d
    mov [rbx], r11d

.col_skip:
    add rbx, 4
    add r12, [FR + F_DXE0]
    add r13, [FR + F_DXE1]
    add r14, [FR + F_DXE2]
    cmp rbx, r15
    jb .col_start

.row_end:
    add r12, [FR + F_DYE0]
    add r13, [FR + F_DYE1]
    add r14, [FR + F_DYE2]
    mov [FR + F_E0ST], r12
    mov [FR + F_E1ST], r13
    mov [FR + F_E2ST], r14
    inc rbp
    cmp rbp, [FR + F_MAXY]
    jb .row_load

.rt_finish:
    add rsp, F_SIZE + 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .rodata align=16
.zero_q: dq 0
.zero_d: dq 0.0
.c255_d: dq 255.0

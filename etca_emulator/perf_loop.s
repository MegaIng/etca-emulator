_start: mov  %r3, 10 ; <- change that as desired; = 1/2 cycle count
        mov  %r2, %r0
loop:   mov  %r1, %r3
        mov  %r0, 1
        call %r2
        mov  %r1, 10
        sth  %r1, 3
        subx %r3, 1
        jnz  loop
        mov  %r0, 0
        mov  %r1, 0
        call %r2
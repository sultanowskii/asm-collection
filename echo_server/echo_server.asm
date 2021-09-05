; BITS 64

global _start


section .data
        STDIN                  equ 0
		STDOUT                 equ 1
        SYS_READ               equ 0
		SYS_WRITE              equ 1
        SYS_CLOSE              equ 3
        SYS_SOCKET             equ 41
        SYS_ACCEPT             equ 43
        SYS_BIND               equ 49
        SYS_LISTEN             equ 50
		SYS_EXIT               equ 60
        EXIT_CODE              equ 0
        s_exit                 db "exit", 0
        s_echo_greetings       db "Type something:", 10, 0
        s_echo_bye             db "Ok bye!!!", 10, 0
        s_serv_running         db "[.] Server is running on port %d.", 10,
                                  "    Usage: (./echo_server.elf <PORT>)", 10, 0
        s_serv_accept_failed   db "[!] Failed to accept client", 10, 0
        s_serv_accept_succsess db "[.] New client accepted", 10, 0
        s_serv_close_succsess  db "[.] Closed connection with client", 10, 0


section .text    
    extern htonl, htons, strlen, strncmp, atoi, sprintf, memset

    _start:
        xor ebp, ebp

        ; if argc > 1 then use custom port
        mov rax, [rsp]
        cmp rax, 1
        ja _start_custom_port
        jmp _start_default_port
    
        _start_custom_port: 
            ; set custom port
            mov rax, [rsp+16]
            mov rdi, rax
            call atoi
            mov edi, eax
            jmp _start_call_main
        
        _start_default_port:
            ; set default port
            mov edi, 5431

        _start_call_main:
        call main

        ; exit(0)
        xor edi, edi
        mov rax, 60
        syscall

    main:
        ; 0    = saved rbp
        ; -16  = sockaddr
        ; -32  = cliaddr
        ; -40  = sockfd
        ; -48  = confd
        ; -56  = addrlen
        ; -60  = port
        push rbp
        mov rbp, rsp
        sub rsp, 72

        ; addrlen = 16
        mov DWORD [rbp-56], 16
        mov DWORD [rbp-60], edi

        ; socket(AF_INET, SOCK_STREAM, 0)
        mov rdi, 2
        mov rsi, 1
        xor edx, edx
        mov rax, SYS_SOCKET
        syscall

        ; socket fd
        mov [rbp-40], rax

        ; sockaddr_in(AF_INET, htons(port), htonl(0), 0)
        ; AF_INET
        mov WORD [rbp-16], 2
        ; port
        mov edi, [rbp-60]
        call htons
        mov WORD [rbp-16+2], ax
        ; INADDR_ANY
        mov rdi, 0
        call htonl
        mov DWORD [rbp-16+4], eax
        ; 0
        mov DWORD [rbp-16+8], 0
        
        ; bind(sockfd, sock_addr_in *, addrlen)
        mov rdi, [rbp-40]
        lea rsi, [rbp-16]
        mov edx, [rbp-56]
        mov rax, SYS_BIND
        syscall

        ; listen(sockfd, 5)
        mov rdi, [rbp-40]
        mov rsi, 5
        mov rax, SYS_LISTEN
        syscall

        ; memset(tmp_text, 0, 128)
        lea rdi, [rel+tmp_text]
        xor esi, esi
        mov rdx, 128
        call memset

        ; formatting ser running string
        mov rdi, rax
        lea rsi, [rel+s_serv_running]
        mov edx, [rbp-60]
        xor eax, eax
        call sprintf

        ; formatted string length
        lea rdi, [rel+tmp_text]
        xor eax, eax
        call strlen

        ; serv is running message
        mov rdi, STDOUT
        lea rsi, [rel+tmp_text]
        mov rdx, rax
        mov rax, SYS_WRITE
        syscall

        main_accept_while:
            ; accept(fd, addr_cli *, addrlen *)
            mov rdi, [rbp-40]
            lea rsi, [rbp-32]
            lea rdx, [rbp-56]
            mov rax, SYS_ACCEPT
            syscall
            mov [rbp-48], eax

            ; success if confd >= 0
            cmp DWORD [rbp-48], 0
            jns main_accepted
            jmp main_accept_failed
            
            main_accepted:
                ; successful accept msg
                mov rdi, STDOUT
                lea rsi, [rel+s_serv_accept_succsess]
                mov rdx, 24
                mov rax, SYS_WRITE
                syscall

                ; echo_worker(confd)
                mov rdi, [rbp-48]
                call echo_worker

                ; close(confd)
                mov rdi, [rbp-48]
                mov rax, SYS_CLOSE
                syscall

                ; successful accept msg
                mov rdi, STDOUT
                lea rsi, [rel+s_serv_close_succsess]
                mov rdx, 34
                mov rax, SYS_WRITE
                syscall

                jmp main_accept_while

        main_accept_failed:
            ; accept failed msg
            mov rdi, STDOUT
            lea rsi, [rel+s_serv_accept_failed]
            mov rdx, 28
            mov rax, SYS_WRITE
            syscall     
        main_end:
            leave
            ret


    echo_worker:
        ; -8  = confd
        ; -16 = text * 
        ; -24 = textlen
        push rbp
        mov rbp, rsp
        sub rsp, 32

        mov [rbp-8], rdi
        lea rax, [rel+cli_text]
        mov [rbp-16], rax

        ; client greetings msg
        mov rdi, [rbp-8]
        lea rsi, [rel+s_echo_greetings]
        mov rdx, 16
        mov rax, SYS_WRITE
        syscall
        
        echo_loop:
            ; read client message
            mov rdi, [rbp-8]
            lea rsi, [rel+cli_text]
            mov rdx, 4096
            mov rax, SYS_READ
            syscall

            ; cli_text length
            mov [rbp-24], rax

            lea rdi, [rel+cli_text]
            lea rsi, [rel+s_exit]
            mov rdx, 4
            call strncmp
            jz echo_exit

            ; send client's message back
            mov rdi, [rbp-8]
            lea rsi, [rel+cli_text]
            mov rdx, [rbp-24]
            mov rax, SYS_WRITE
            syscall
            jmp echo_loop

        echo_exit:
            ; send client's message back
            mov rdi, [rbp-8]
            lea rsi, [rel+s_echo_bye]
            mov rdx, 10
            mov rax, SYS_WRITE
            syscall

            leave
            ret

section .bss
    ; client's input
    cli_text resb 4096
    ; formatted string
    tmp_text resb 128

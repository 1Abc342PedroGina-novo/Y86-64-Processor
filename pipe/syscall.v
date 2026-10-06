`timescale 1ns / 1ps

module syscall(
    input [3:0] icode,              // Código da instrução atual vindo do Fetch/Decode
    input [63:0] curr_pc,           // Endereço (PC) da instrução syscall atual
    input [63:0] rflags_in,         // Flags atuais da ULA (Zero, Sign, Overflow)
    
    output reg syscall_interrupt,   // Flag que avisa o processador para congelar/limpar o pipeline
    output reg [63:0] next_pc,      // Novo PC para onde o processador deve pular (Vetor do OS)
    output reg [63:0] saved_pc,     // Valor a ser gravado em %rcx (endereço de retorno)
    output reg [63:0] saved_flags   // Valor a ser gravado em %r11
    );

    // Endereço fixo na memória onde o Kernel do seu sistema operacional vai começar.
    // No x86_64 real isso fica em um registrador MSR (IA32_LSTAR), aqui fixamos para fins educacionais.
    parameter KERNEL_ENTRY_POINT = 64'h0000_0000_0000_0F00; 

    always @(*) begin
        // Verifica se o opcode corresponde a uma chamada de sistema.
        // Vamos assumir o opcode 4'b1100 (12 em decimal, que estava livre no Y86-64) para o SYSCALL.
        if (icode == 4'b1100) begin
            syscall_interrupt = 1'b1;
            next_pc           = KERNEL_ENTRY_POINT; // Força o PC a pular para o Kernel
            saved_pc          = curr_pc + 64'd2;   // Salva o PC de retorno (assumindo tamanho de instrução de 2 bytes)
            saved_flags       = rflags_in;         // Copia o estado das flags de condição
        end
        else begin
            syscall_interrupt = 1'b0;
            next_pc           = 64'b0;
            saved_pc          = 64'b0;
            saved_flags       = 64'b0;
        end
    end

endmodule

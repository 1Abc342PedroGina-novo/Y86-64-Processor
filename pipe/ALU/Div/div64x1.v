`timescale 1ns / 1ps

module div64x1(
    input signed [63:0] rdx_in,   // Parte alta do dividendo (64 bits)
    input signed [63:0] rax_in,   // Parte baixa do dividendo (64 bits)
    input signed [63:0] b,        // Divisor (64 bits)
    
    output reg signed [63:0] quot, // Quociente (vai para %rax no x86_64)
    output reg signed [63:0] rem,  // Resto/Remanescente (vai para %rdx no x86_64)
    output reg div_error           // Flag de erro: ativada em divisão por zero ou overflow
    );

    reg signed [127:0] dividend;
    reg signed [127:0] temp_quot;
    reg signed [127:0] temp_rem;

    always @(*) begin
        // Monta o dividendo de 128 bits combinando RDX (alto) e RAX (baixo)
        dividend = {rdx_in, rax_in};
        
        // Inicialização padrão das flags e saídas
        div_error = 1'b0;
        quot      = 64'b0;
        rem       = 64'b0;

        if (b == 64'b0) begin
            // 1. Proteção de Hardware contra Divisão por Zero (#DE - Divide Error Exception)
            div_error = 1'b1;
        end
        else begin
            // Realiza as operações matemáticas em 128 bits
            temp_quot = dividend / b;
            temp_rem  = dividend % b;

            // 2. Proteção contra Overflow de Divisão (Quociente não cabe em 64 bits com sinal)
            if (temp_quot < -64'sh8000_0000_0000_0000 || temp_quot > 64'sh7FFF_FFFF_FFFF_FFFF) begin
                div_error = 1'b1;
            end
            else begin
                quot = temp_quot[63:0];
                rem  = temp_rem[63:0];
            end
        end
    end

endmodule

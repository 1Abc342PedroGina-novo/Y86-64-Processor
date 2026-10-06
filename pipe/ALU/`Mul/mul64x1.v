`timescale 1ns / 1ps

module mul64x1(
    input signed [63:0] a,       // Multiplicando (64 bits com sinal)
    input signed [63:0] b,       // Multiplicador (64 bits com sinal)
    output reg signed [63:0] prod, // 64 bits menos significativos do produto
    output reg overflow          // Flag de overflow (indica se o resultado estourou 64 bits)
    );

    reg signed [127:0] full_prod; // Registrador temporário para armazenar o produto completo de 128 bits

    always @(*) begin
        // Realiza a multiplicação de 64-bit com sinal gerando 128-bit
        full_prod = a * b;
        
        // O resultado final assume os 64 bits inferiores, igual ao comportamento do x86_64 real
        prod = full_prod[63:0];
        
        // No x86_64 real, as flags de Carry (CF) e Overflow (OF) do IMUL são ativadas 
        // se o produto completo não couber estritamente em 64 bits com sinal.
        // Verificamos se estendeu o sinal corretamente: se os 64 bits superiores são todos iguais ao bit de sinal do resultado (prod[63]).
        if (full_prod[127:63] == {65{prod[63]}}) begin
            overflow = 1'b0; // O resultado coube perfeitamente em 64 bits com sinal
        end
        else begin
            overflow = 1'b1; // Houve estouro aritmético (overflow)
        end
    end

endmodule

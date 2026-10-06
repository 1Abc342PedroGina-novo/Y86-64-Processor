`timescale 1ns / 1ps

module shift64x1(
    input [63:0] a,       // O valor de 64 bits que será deslocado
    input [5:0]  shamt,   // Quantidade de deslocamento (0 a 63 bits -> 6 bits bastam)
    input        dir,     // Direção do deslocamento: 0 = Esquerda (SHL), 1 = Direita (SHR)
    output reg [63:0] ans // O resultado final de 64 bits
    );

    // Bloco puramente combinacional para calcular o deslocamento
    always @(*) begin
        if (dir == 1'b0) begin
            // Deslocamento Lógico para a Esquerda (SHL)
            // Preenche com zeros à direita
            ans = a << shamt;
        end
        else begin
            // Deslocamento Lógico para a Direita (SHR)
            // Preenche com zeros à esquerda
            ans = a >> shamt;
        end
    end

endmodule

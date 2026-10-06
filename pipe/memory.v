`timescale 1ns / 1ps

module memory(
  clk,icode,valA,valB,valE,valP,valM,datamem,
  rem_in, rem_out // Novas portas para propagar o resto da divisão do IDIV
);

  input clk;
  
  input [3:0] icode;
  input [63:0] valA;
  input [63:0] valB;
  input [63:0] valE;
  input [63:0] valP;
  input signed [63:0] rem_in; // Recebe o resto vindo do estágio de Execute
  
  output reg [63:0] valM;
  output reg [63:0] datamem;
  output reg signed [63:0] rem_out; // Passa o resto para o estágio de Write Back

  reg [63:0] data_mem[0:255];

  // --- LEITURA DA MEMÓRIA (Bloco Combinacional) ---
  always@(*)
  begin
    // Inicialização padrão para evitar latches
    valM = 64'b0; 
    datamem = data_mem[valE];
    rem_out = rem_in; // Propaga o resto diretamente para o próximo estágio

    if(icode==4'b0101) //mrmovq
    begin
      valM=data_mem[valE];
    end
    else if(icode==4'b1001) //ret
    begin
      valM=data_mem[valA];
    end
    else if(icode==4'b1011) //popq
    begin
      valM=data_mem[valE];
    end
  end

  // --- ESCRITA NA MEMÓRIA (Bloco Síncrono com o Clock) ---
  // Modificado para posedge clk para garantir estabilidade no pipeline
  always@(posedge clk)
  begin
    if(icode==4'b0100) //rmmovq
    begin
      data_mem[valE] <= valA;
    end
    else if(icode==4'b1000) //call
    begin
      data_mem[valE] <= valP;
    end
    else if(icode==4'b1010) //pushq
    begin
      data_mem[valE] <= valA;
    end
  end
  
endmodule

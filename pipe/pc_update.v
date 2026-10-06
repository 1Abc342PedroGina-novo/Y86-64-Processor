`timescale 1ns / 1ps

module pc_update(
  clk,PC,cnd,icode,valC,valM,valP,
  div_error,                    // Nova entrada: sinaliza erro de divisão (da ULA)
  updated_pc
);
  input clk;
  input cnd;
  input [3:0] icode;
  input [63:0] valC;
  input [63:0] valP;
  input [63:0] valM;
  input [63:0] PC;
  input div_error;              // Vem lá do bloco execute/ULA
  output reg [63:0] updated_pc;

  // Vetores de interrupção em endereços de memória fixos (Estilo x86_64 Real)
  parameter SYSCALL_HANDLER_PC = 64'h0000_0000_0000_0F00; // Endereço do Kernel para chamadas de sistema
  parameter DIV_ERROR_HANDLER_PC = 64'h0000_0000_0000_0E00; // Endereço para tratar erro de divisão por zero

  always@(*)
  begin
    // 1. Prioridade Máxima: Erros Críticos de Hardware (Exceções de divisão)
    if (div_error == 1'b1) 
    begin
      updated_pc = DIV_ERROR_HANDLER_PC; // Desvia o PC para o tratador de erros do OS
    end
    
    // 2. Nova Instrução: SYSCALL (Opcode 4'b1100)
    else if (icode == 4'b1100) 
    begin
      updated_pc = SYSCALL_HANDLER_PC; // Salta direto para a base do Kernel
    end
    
    // 3. Instruções Originais do Y86-64
    else if(icode==4'b0111) //jxx
    begin
      if(cnd==1'b1)
      begin
        updated_pc=valC;
      end
      else
      begin
        updated_pc=valP;
      end
    end
    else if(icode==4'b1000) //call
    begin
      updated_pc=valC;
    end
    else if(icode==4'b1001) //ret
    begin
      updated_pc=valM;
    end
    
    // 4. Fluxo Sequencial Padrão
    else
    begin
      updated_pc=valP;
    end
  end

endmodule

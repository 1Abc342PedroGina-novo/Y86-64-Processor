`timescale 1ns / 1ps

`include "./ALU/Add/add64x1.v"
`include "./ALU/Add/add1x1.v"
`include "./ALU/Sub/sub64x1.v"
`include "./ALU/Sub/not/not1x1.v"
`include "./ALU/Sub/not/not64x1.v"
`include "./ALU/Xor/xor64x1.v"
`include "./ALU/Xor/xor1x1.v"
`include "./ALU/And/and64x1.v"
`include "./ALU/And/and1x1.v"
// Inclusão dos novos módulos de arquitetura estendida x86_64
`include "./ALU/Shift/shift64x1.v"
`include "./ALU/Mul/mul64x1.v"
`include "./ALU/Div/div64x1.v"

module alu(
  input [3:0]control,             // Expandido para 4 bits para suportar as novas operações
  input signed [63:0]a,           // No IDIV, este será o RDX (Parte alta do dividendo)
  input signed [63:0]b,           // Operando B tradicional (ou Divisor no IDIV)
  input signed [63:0]rax_in,       // Nova entrada necessária exclusivamente para a parte baixa do dividendo do IDIV
  
  output signed [63:0]ans,        // Resposta principal / Quociente no IDIV
  output signed [63:0]rem_out,    // Nova saída para o Resto da Divisão (obrigatório para IDIV do x86_64)
  output overflow,
  output div_error                // Nova saída indicando erro de divisão por zero ou estouro de divisão
);
  
  // Fios de interconexão originais
  wire signed [63:0]ans1;
  wire signed [63:0]ans2;
  wire signed [63:0]ans3;
  wire signed [63:0]ans4;
  wire overflow1;
  wire overflow2;

  // Novos fios de interconexão para as operações x86_64 estendidas
  wire signed [63:0]ans_shl;
  wire signed [63:0]ans_shr;
  wire signed [63:0]ans_mul;
  wire overflow_mul;
  wire signed [63:0]ans_div;
  wire signed [63:0]rem_div;
  wire error_div;

  // Registradores internos para o bloco multiplexador combinacional
  reg signed [63:0]ansfinal;
  reg signed [63:0]remfinal;
  reg overflowfinal;
  reg div_error_final;

  // Instanciações Originais do Y86-64
  add64x1 g1(a, b, ans1, overflow1); 
  sub64x1 g2(a, b, ans2, overflow2);
  and64x1 g3(a, b, ans3);
  xor64x1 g4(a, b, ans4);

  // Novas Instanciações para aproximar do x86_64 Real
  // Para os Shifts, passamos os 6 bits inferiores de 'b' como a quantidade de deslocamento (shamt)
  shift64x1 g5(a, b[5:0], 1'b0, ans_shl); // SHL: direção = 0
  shift64x1 g6(a, b[5:0], 1'b1, ans_shr); // SHR: direção = 1
  mul64x1   g7(a, b, ans_mul, overflow_mul);
  div64x1   g8(a, rax_in, b, ans_div, rem_div, error_div); // a = RDX, rax_in = RAX, b = Divisor

  always @(*)
  begin
    // Inicialização padrão para evitar a geração de latches indesejados
    ansfinal        = 64'b0;
    remfinal        = 64'b0;
    overflowfinal   = 1'b0;
    div_error_final = 1'b0;

    case(control)
      4'b0000: begin // ADD
          ansfinal      = ans1;
          overflowfinal = overflow1;
        end
      4'b0001: begin // SUB
          ansfinal      = ans2;
          overflowfinal = overflow2;
        end    
      4'b0010: begin // AND
          ansfinal      = ans3;
          overflowfinal = 1'b0;
        end
      4'b0011: begin // XOR
          ansfinal      = ans4;
          overflowfinal = 1'b0;
        end
      4'b0100: begin // SHL (Novo)
          ansfinal      = ans_shl;
          overflowfinal = 1'b0; 
        end
      4'b0101: begin // SHR (Novo)
          ansfinal      = ans_shr;
          overflowfinal = 1'b0;
        end
      4'b0110: begin // IMUL (Novo)
          ansfinal      = ans_mul;
          overflowfinal = overflow_mul;
        end
      4'b0111: begin // IDIV (Novo)
          ansfinal        = ans_div;
          remfinal        = rem_div;
          div_error_final = error_div;
          overflowfinal   = 1'b0; // O erro de divisão já cobre o estouro neste modelo
        end
      default: begin
          ansfinal        = 64'b0;
          remfinal        = 64'b0;
          overflowfinal   = 1'b0;
          div_error_final = 1'b0;
        end
    endcase
  end  

  // Atribuições contínuas de saída
  assign ans       = ansfinal;
  assign rem_out   = remfinal;
  assign overflow  = overflowfinal;
  assign div_error = div_error_final;

endmodule

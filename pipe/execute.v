`timescale 1ns / 1ps

`include "./ALU/alu.v"

module execute(
  input clk,
  input rst,
  
  // Barramentos de Controle e Sinais do Pipeline
  input [3:0]  icode,       // Código da Instrução Principal
  input [3:0]  ifun,        // Função/Variação da Instrução (Opcodes estendidos)
  input [63:0] valA,        // Operando A vindo do Decode (Ex: conteúdo de rA ou %rax)
  input [63:0] valB,        // Operando B vindo do Decode (Ex: conteúdo de rB ou %rdx)
  input [63:0] valC,        // Valor Imediato (Constantes de deslocamento ou endereçamento)
  input [63:0] valP,        // Program Counter da próxima instrução sequencial
  
  // Saídas de Controle e Dados Calculados
  output reg [63:0] valE,   // Resultado Principal da Execução / Endereço Efetivo
  output reg [63:0] rem_out,// Resto da divisão (Exclusivo para IDIV -> %rdx)
  output reg        cnd,    // Flag de Condição Satisfeita (Para saltos e CMOVxx)
  
  // Registradores do Sistema de Flags (RFLAGS x86_64)
  output reg zf,            // Zero Flag
  output reg sf,            // Sign Flag
  output reg of,            // Overflow Flag
  output reg cf,            // Carry Flag (Novo: Essencial para x86_64 Real)
  output reg pf,            // Parity Flag (Novo: Paridade dos 8 bits inferiores)
  output reg af,            // Auxiliary Carry Flag (Novo: Aritmética BCD/Nibble)
  
  // Linhas de Exceções e Interrupções de Hardware (x86_64 Exception Handling)
  output reg div_error,     // Erro Crítico: Divisão por zero ou Quociente estourado (#DE)
  output reg stack_fault,   // Erro Crítico: Estouro de limite físico de pilha (#SS)
  output reg gp_fault       // Erro Crítico: Falha Geral de Proteção de Hardware (#GP)
);

  // --- DECLARAÇÃO DE SINAIS INTERNOS E CONEXÕES DA ULA ---
  reg [3:0]  control;       // Seletor expandido de 4 bits para a nova ULA
  reg signed [63:0] alu_a;  // Entrada A dedicada da ULA
  reg signed [63:0] alu_b;  // Entrada B dedicada da ULA
  reg signed [63:0] rax_in; // Entrada dedicada para a parte baixa do dividendo (IDIV)

  wire signed [63:0] alu_ans; // Resposta principal vinda da ULA
  wire signed [63:0] alu_rem; // Resto calculado vindo da ULA
  wire alu_overflow;          // Flag de estouro aritmético gerada pela ULA
  wire alu_div_error;         // Flag de erro de divisão gerada pela ULA

  // Instanciação Única e Otimizada da Nova ULA Estendida de 4 Bits
  alu alu_inst(
    .control(control),
    .a(alu_a),
    .b(alu_b),
    .rax_in(rax_in),
    .ans(alu_ans),
    .rem_out(alu_rem),
    .overflow(alu_overflow),
    .div_error(alu_div_error)
  );

  // --- GATES COMBINACIONAIS AUXILIARES PARA LÓGICA DE CONDIÇÃO ---
  reg xin1, xin2, oin1, oin2, ain1, ain2, nin1;
  wire xout, oout, aout, nout;

  xor g1(xout, xin1, xin2);
  or  g2(oout, oin1, oin2);
  and g3(aout, ain1, ain2);
  not g4(nout, nin1);

  // --- BLOCO COMPORTAMENTAL: GERAÇÃO E ATUALIZAÇÃO DO RFLAGS ---
  // No x86_64, as flags são atualizadas na borda do clock apenas se a instrução for estritamente aritmética/lógica
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      zf <= 1'b0;
      sf <= 1'b0;
      of <= 1'b0;
      cf <= 1'b0;
      pf <= 1'b0;
      af <= 1'b0;
    end
    else begin
      // Opcode 4'b0110 corresponde ao grupo de operações aritméticas e lógicas (OPq)
      if (icode == 4'b0110) begin
        zf <= (alu_ans == 64'b0);
        sf <= alu_ans[63]; // Bit de sinal mais significativo
        of <= alu_overflow;
        
        // Cáculo de Paridade (PF): Verifica o número de bits 1 nos 8 bits menos significativos (par = 1, ímpar = 0)
        pf <= ~(^alu_ans[7:0]);
        
        // Lógica de Carry (CF) baseada na operação selecionada via ifun
        if (ifun == 4'b0000) begin // ADD
          cf <= (alu_ans < alu_a);
        end
        else if (ifun == 4'b0001) begin // SUB
          cf <= (alu_a < alu_b);
        end
        else begin
          cf <= 1'b0; // Operações lógicas (AND, XOR, SHL, SHR) limpam a Carry Flag no x86
        end
        
        // Auxiliary Carry (AF): Detecção de carry no nível do nibble inferior (bit 3 para bit 4)
        af <= (alu_a[3] & alu_b[3]) | (alu_a[3] & ~alu_ans[3]) | (b[3] & ~alu_ans[3]);
      end
    end
  end

  // --- BLOCO COMBINACIONAL: DECODIFICAÇÃO E EXECUÇÃO MASSIVA ---
  always @(*) begin
    // Inicialização compulsória de segurança de todas as saídas (Evita geração de Latches Parasitas)
    valE            = 64'b0;
    rem_out         = 64'b0;
    cnd             = 1'b0;
    control         = 4'b1111; // Estado inativo / sem operação
    alu_a           = 64'b0;
    alu_b           = 64'b0;
    rax_in          = 64'b0;
    div_error       = 1'b0;
    stack_fault     = 1'b0;
    gp_fault        = 1'b0;
    
    // Conexões padrão dos gates lógicos auxiliares
    xin1 = 1'b0; xin2 = 1'b0; oin1 = 1'b0; oin2 = 1'b0; ain1 = 1'b0; ain2 = 1'b0; nin1 = 1'b0;

    case (icode)
      
      // ==========================================
      // 4'b0000: NOP (No Operation) - Estilo x86_64
      // ==========================================
      4'b0000: begin
        valE = 64'b0;
      end

      // ==========================================
      // 4'b0001: HALT - Para Execução da CPU
      // ==========================================
      4'b0001: begin
        valE = 64'b0;
      end

      // ==========================================
      // 4'b0010: CMOVxx / RRMOVQ (Movimentações Condicionais)
      // ==========================================
      4'b0010: begin
        case (ifun)
          4'b0000: cnd = 1'b1; // rrmovq (Incondicional)
          
          4'b0001: begin // cmovle / jle -> (sf ^ of) | zf
            xin1 = sf; xin2 = of;
            if (xout || zf) cnd = 1'b1;
          end
          
          4'b0010: begin // cmovl / jl -> sf ^ of
            xin1 = sf; xin2 = of;
            if (xout) cnd = 1'b1;
          end
          
          4'b0011: begin // cmove / je -> zf
            if (zf) cnd = 1'b1;
          end
          
          4'b0100: begin // cmovne / jne -> !zf
            nin1 = zf;
            if (nout) cnd = 1'b1;
          end
          
          4'b0101: begin // cmovge / jge -> !(sf ^ of)
            xin1 = sf; xin2 = of; nin1 = xout;
            if (nout) cnd = 1'b1;
          end
          
          4'b0110: begin // cmovg / jg -> !(sf ^ of) & !zf
            xin1 = sf; xin2 = of; nin1 = xout;
            if (nout && !zf) cnd = 1'b1;
          end
          
          4'b0111: begin // cmovb / jb (Aritmética sem sinal: abaixo / Carry ativado)
            if (cf) cnd = 1'b1;
          end
          
          4'b1000: begin // cmovbe / jbe (Aritmética sem sinal: abaixo ou igual)
            if (cf || zf) cnd = 1'b1;
          end
          
          4'b1001: begin // cmova / ja (Aritmética sem sinal: acima)
            if (!cf && !zf) cnd = 1'b1;
          end
          
          4'b1010: begin // cmovae / jae (Aritmética sem sinal: acima ou igual)
            if (!cf) cnd = 1'b1;
          end
          
          default: gp_fault = 1'b1; // Extensão de Opcode Inválida
        endcase
        valE = 64'd0 + valA; // Transmite o dado original para gravação futura
      end

      // ==========================================
      // 4'b0011: IRMOVQ (Carrega constante de 64 bits para registrador)
      // ==========================================
      4'b0011: begin
        valE = 64'd0 + valC; // Passa o valor imediato diretamente
      end

      // ==========================================
      // 4'b0100: RMMOVQ (Store: Registrador para a Memória RAM)
      // ==========================================
      4'b0100: begin
        valE = valB + valC; // Calcula endereço efetivo na memória: Base + Deslocamento
      end

      // ==========================================
      // 4'b0101: MRMOVQ (Load: Memória RAM para o Registrador)
      // ==========================================
      4'b0101: begin
        valE = valB + valC; // Calcula endereço efetivo na memória: Base + Deslocamento
      end

      // ==========================================
      // 4'b0110: ARITMÉTICA E LÓGICA ESTENDIDA (OPq)
      // ==========================================
      4'b0110: begin
        case (ifun)
          4'b0000: begin // ADDQ
            control = 4'b0000;
            alu_a   = valA;
            alu_b   = valB;
            valE    = alu_ans;
          end
          
          4'b0001: begin // SUBQ
            control = 4'b0000; // ULA trata como subtração baseada no fluxo
            control = 4'b0001;
            alu_a   = valA;
            alu_b   = valB;
            valE    = alu_ans;
          end
          
          4'b0010: begin // ANDQ
            control = 4'b0010;
            alu_a   = valA;
            alu_b   = valB;
            valE    = alu_ans;
          end
          
          4'b0011: begin // XORQ
            control = 4'b0011;
            alu_a   = valA;
            alu_b   = valB;
            valE    = alu_ans;
          end
          
          4'b0100: begin // SHLQ (Novo: Shift Left Combinacional)
            control = 4'b0100;
            alu_a   = valA; // O valor a ser deslocado
            alu_b   = valB; // Contém a contagem de deslocamento em valB[5:0]
            valE    = alu_ans;
          end
          
          4'b0101: begin // SHRQ (Novo: Shift Right Combinacional)
            control = 4'b0101;
            alu_a   = valA;
            alu_b   = valB;
            valE    = alu_ans;
          end
          
          4'b0110: begin // IMULQ (Novo: Multiplicação de Hardware de 64 bits)
            control = 4'b0110;
            alu_a   = valA;
            alu_b   = valB;
            valE    = alu_ans;
          end
          
          4'b0111: begin // IDIVQ (Novo: Divisão Avançada x86_64 de 128-bit por 64-bit)
            control = 4'b0111;
            alu_a   = valB;     // Na arquitetura estruturada, passamos o RDX para a entrada A
// ==========================================
// 4'b0101 / 4'b0110: DIV / REM
// ==========================================
    rax_in  = valA;      // Passamos o RAX para a porta dedicada rax_in
    alu_b   = valC;      // O divisor vem do imediato ou registrador secundário mapeado em valC
    valE    = alu_ans;   // Quociente gerado vai para valE (destino final: %rax)
    rem_out = alu_rem;   // Resto gerado vai para o barramento rem_out (destino final: %rdx)

    if (alu_div_error) begin
        div_error = 1'b1; // Dispara exceção de divisão em tempo real para congelar o pipeline
    end
end

default: gp_fault = 1'b1;
endcase
end

// ==========================================
// 4'b0111: JXX (Saltos Condicionais e Incondicionais)
// ==========================================
4'b0111: begin
    // A lógica de avaliação herda os mesmos gates do CMOVxx gerados acima
    case (ifun)
        4'b0000: cnd = 1'b1; // jmp (Sempre salta)

        4'b0001: begin // jle
            xin1 = sf; xin2 = of;
            if (xout || zf) cnd = 1'b1;
        end

        4'b0010: begin // jl
            xin1 = sf; xin2 = of;
            if (xout) cnd = 1'b1;
        end

        4'b0011: begin // je
            if (zf) cnd = 1'b1;
        end

        4'b0100: begin // jne
            nin1 = zf;
            if (nout) cnd = 1'b1;
        end

        4'b0101: begin // jge
            xin1 = sf; xin2 = of; nin1 = xout;
            if (nout) cnd = 1'b1;
        end

        4'b0110: begin // jg
            xin1 = sf; xin2 = of; nin1 = xout;
            if (nout && !zf) cnd = 1'b1;
        end

        4'b0111: begin // jb / jc (Salta se houver Carry)
            if (cf) cnd = 1'b1;
        end

        4'b1000: begin // jbe
            if (cf || zf) cnd = 1'b1;
        end

        4'b1001: begin // ja
            if (!cf && !zf) cnd = 1'b1;
        end

        default: gp_fault = 1'b1;
    endcase
end

// ==========================================
// 4'b1000: CALL (Chama sub-rotina / função)
// ==========================================
4'b1000: begin
    // Atualiza ponteiro de pilha (%rsp - 8) para alocar espaço para o PC de retorno
    valE = -64'd8 + valB;

    // Proteção contra estouro de pilha física inferior
    if (valE < 64'h0000_0000_0000_0040) begin
        stack_fault = 1'b1;
    end
end

// ==========================================
// 4'b1001: RET (Retorna de uma sub-rotina)
// ==========================================
4'b1001: begin
    // Desaloca o espaço limpando a pilha (%rsp + 8)
    valE = 64'd8 + valB;
end

// ==========================================
// 4'b1010: PUSHQ (Insere dados na Pilha de Memória)
// ==========================================
4'b1010: begin
    valE = -64'd8 + valB; // Decrementa %rsp de 8 bytes

    if (valE < 64'h0000_0000_0000_0040) begin
        stack_fault = 1'b1;
    end
end

// ==========================================
// 4'b1011: POPQ (Remove dados da Pilha de Memória)
// ==========================================
4'b1011: begin
    valE = 64'd8 + valB; // Incrementa %rsp de 8 bytes
end

// ==========================================
// 4'b1100: SYSCALL (Novo: Chamada de Sistema)
// ==========================================
4'b1100: begin
    valE = valP; // Transmite o endereço de retorno para salvar no %rcx futuras rotinas de Decode/WB
end

// ==========================================
// 4'b1101: STRING MANIPULATION (Novo: Ex: MOVSB/STOSB-like)
// ==========================================
4'b1101: begin
    // No x86_64, instruções de string operam incrementando/decrementando os ponteiros %rsi e %rdi
    if (ifun == 4'b0000) begin
        valE = valA + 64'd1; // Incrementa ponteiro se a Direction Flag (DF) for 0
    end
    else begin
        valE = valA - 64'd1; // Decrementa se DF for 1
    end
end

// ==========================================
// 4'b1110: EXTENSÃO ARITMÉTICA VETORIAL BÁSICA
// ==========================================
4'b1110: begin
    // Executa processamento aritmético simulando registradores SIMD/XMM em blocos mascarados
    control = 4'b0000;
    alu_a   = valA;
    alu_b   = valB;
    valE    = alu_ans ^ valC; // Aplica máscara vetorial via imediato valC
end

default: begin
    gp_fault = 1'b1; // Qualquer opcode desconhecido dispara Falha Geral de Proteção
end
endcase
end

endmodule

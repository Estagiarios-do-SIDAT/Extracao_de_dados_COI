# Consultas do Power BI — COI

Este documento explica como funcionam as consultas que alimentam o painel do
COI: o que cada uma entrega, que página do painel ela atende, como o período é
calculado e como conferir o resultado depois de uma atualização.

São **6 consultas**, todas em `powerbi/`, cada uma com o nome da sua consulta de
referência em `queries/` seguido de `_power_bi`. Cada consulta do Power BI
aplica **a mesma regra** da sua referência; muda apenas o que é necessário para
o uso no painel, marcado no SQL com `[POWER BI]`. O texto SQL de cada uma fica
incorporado ao relatório, na etapa `Sql` da sua consulta do Power Query, e o
período vem de um único parâmetro, `QtdMesesCompletosCOI` (seções 3 e 7).

As regras de cálculo — quem conta como Registrado, quem conta como Encerrado, de
onde vem cada data, a quem se atribui cada registro e cada encerramento — estão
em `docs/coi-calculation.md`. Este documento trata do que é próprio do Power BI.

---

## Índice

1. [As 6 consultas do painel](#1-as-6-consultas-do-painel)
2. [Consultas que ficam só em `queries/`](#2-consultas-que-ficam-só-em-queries)
3. [Período automático](#3-período-automático)
4. [Grupo alvo de Encerrados](#4-grupo-alvo-de-encerrados)
5. [Colunas de diagnóstico do detalhe](#5-colunas-de-diagnóstico-do-detalhe)
6. [Montagem das páginas](#6-montagem-das-páginas)
7. [Manutenção no Power Query](#7-manutenção-no-power-query)
8. [Conferência depois de atualizar](#8-conferência-depois-de-atualizar)
9. [Limitações](#9-limitações)
10. [Alertas de manutenção](#10-alertas-de-manutenção)

Há uma versão resumida desta documentação em HTML, para exibir dentro do painel
no visual **HTML Content**: `powerbi/documentacao-powerbi-coi.html`. Ela deriva
deste arquivo; se os dois divergirem, **vale este**.

---

## 1. As 6 consultas do painel

O painel tem sete páginas:

| # | Página | Finalidade | Consulta |
|---|---|---|---|
| 1 | **Início** | navegação para as demais páginas | nenhuma |
| 2 | **Visão Geral** | totais de Registrados e Encerrados, evolução Ano → Mês → Dia e a lista dos chamados | detalhe de registrados, encerrados, diário |
| 3 | **Por Hora** | distribuição pelas 24 horas do dia, Registrados ou Encerrados | Registrados × Encerrados por hora |
| 4 | **Por Membro** | quantos chamados cada conta registrou e quantos encerramentos cada responsável tem — critério do fornecedor | por membro |
| 5 | **Por Tipo** | Incidente × Solicitação, em Registrados e em Encerrados | detalhe de registrados, encerrados |
| 6 | **Satisfação** | pesquisas de satisfação dos chamados encerrados | satisfação, detalhe |
| 7 | **Documentação** | indicadores, regras, fontes, consultas e funcionamento do painel | nenhuma: exibe `powerbi/documentacao-powerbi-coi.html` |

As cinco páginas analíticas (2 a 6) usam estas consultas:

| Consulta do Power BI | Granularidade | Colunas | Páginas |
|---|---|---|---|
| `consulta_coi_registrados_detalhe_power_bi.sql` | 1 linha por SDM **registrado** | 29, entre elas `SDM`, `Categoria`, `Resumo`, `DataRegistroCOI`, `DataRegistro`, `HoraRegistro`, `Tipo`, `RegistradorNome`, `FormaRegistroCOI` | Visão Geral (cartão e tabela), Por Tipo |
| `consulta_coi_encerrados_power_bi.sql` | 1 linha por SDM **encerrado** | 14: `SDM`, `Tipo Chamado`, `Símbolo` (categoria), `Resumo`, `Item de Configuração`, `Prioridade`, `Status`, `Código Status`, `Data de Abertura`, `Data de Encerramento`, `Data de Resolução`, `Responsável`, `Grupo Atual`, `UUID Grupo Atual` | Visão Geral (cartão e tabela), Por Tipo |
| `consulta_coi_registrados_encerrados_diario_power_bi.sql` | 1 linha por **dia** do período, inclusive dias sem movimento | `Dia`, `Registrados`, `Encerrados` | Visão Geral (gráfico Ano → Mês → Dia) |
| `consulta_coi_registrados_encerrados_por_hora_power_bi.sql` | 1 linha por **mês e hora** (24 por mês, inclusive zero) | `Ano`, `Mes`, `MesAno`, `Hora`, `HoraLabel`, `Registrados`, `Encerrados` | Por Hora |
| `consulta_coi_registrados_encerrados_por_membro_power_bi.sql` | 1 linha por **mês e conta** com registro ou encerramento | `Ano`, `Mes`, `MesAno`, `MembroUUID`, `MembroUserID`, `Membro`, `TipoConta`, `Registrados`, `Encerrados`, `EncerradosComoResponsavel` | Por Membro |
| `consulta_coi_pesquisa_satisfacao_encerrados_detalhe_power_bi.sql` | 1 linha por SDM **encerrado**, com a pesquisa | `SDM`, `TipoChamado`, `DataEncerramento`, `Ano`, `Mes`, `MesAno`, `StatusSatisfacao`, `PerguntaAvaliada`, `RespostaSatisfacao`, `QtdPerguntasRespondidas`, `DataPesquisa`, `PesquisaSolicitada`, `QtdSolicitacoesPesquisa`, `DataSolicitacaoPesquisa`, `SolicitacaoPesquisa` | Satisfação |

Todas devolvem **um único resultado**, com as colunas da referência, na mesma
ordem. Nenhuma tem resultado empilhado.

**Registrados e Encerrados são populações diferentes**, cada uma com a sua data:

| | Regra | Data que alimenta ano, mês, dia e hora |
|---|---|---|
| Registrados | primeira entrada no COI (bloco canônico) | `DataRegistroCOI` |
| Encerrados | fechamento no grupo alvo | `Data de Encerramento` (`close_date`) |

**Equivalência conferida:** para o mesmo período, cada consulta do Power BI
devolve exatamente o resultado da sua consulta de referência — mesmas colunas,
mesmas linhas, mesmos valores.

Três consultas são novas (criadas para o painel, com referência em `queries/`):

- **Registrados × Encerrados por hora** — as duas séries na mesma linha, cada
  uma com a sua regra e a sua hora: `DataRegistroCOI` para Registrados,
  `close_date` para Encerrados, nunca uma no lugar da outra;
- **Registrados × Encerrados por membro** — quem registrou e a quem se atribui
  cada encerramento, com a classificação da conta (seção 6);
- **Satisfação, detalhe** — a classificação da pesquisa chamado a chamado, com
  data, para o filtro Mês/Ano.

---

## 2. Consultas que ficam só em `queries/`

Saíram de `powerbi/` (continuam em `queries/` e recuperáveis pelo histórico Git)
porque não alimentam nenhum visual do painel:

| Consulta de referência | Por que não está no painel |
|---|---|
| `consulta_coi_registrados_mensal.sql` | Não há página Por Mês; o mês sai da hierarquia de datas do diário e dos detalhes |
| `consulta_coi_registrados_por_registrador.sql` | Agrega a mesma população do detalhe por quem abriu, sem mês; a página Por Membro usa a consulta por membro |
| `consulta_coi_registrados_por_evidencia.sql` | Auditoria da composição por evidência |
| `consulta_coi_registrados_validacao.sql` | Asserções de sanidade da regra de Registrados |
| `consulta_coi_registrados_membros.sql` | Conciliação com o relatório do fornecedor: conta pela abertura, com lista de analistas fixa por período (FEV, MAR, JUN) |
| `consulta_coi_registrados_total_com_tecnicos.sql` | Conciliação com o fornecedor, períodos fixos |
| `consulta_coi_registrados_universo_bruto.sql` | Auditoria das contas técnicas, períodos fixos |
| `consulta_coi_pesquisa_satisfacao_encerrados.sql` | Resumo e lista sem data, que não acompanham o filtro Mês/Ano; o detalhe novo traz a mesma classificação por chamado |
| `consulta_coi_registrados_por_hora.sql` | A série `Registrados` da consulta Registrados × Encerrados por hora; referência por hora só de Registrados |
| `consulta_coi_encerrados_por_hora.sql` | A série `Encerrados` da consulta Registrados × Encerrados por hora; referência por hora só de Encerrados |

Elas continuam sendo a ferramenta de auditoria e de conciliação: rodar
`consulta_coi_registrados_validacao.sql` num período confere a regra de
Registrados que o painel usa.

---

## 3. Período automático

O período é calculado a cada atualização, e é **o mesmo nas 6 consultas** —
assim todas as páginas enxergam os mesmos meses carregados:

| Limite | Valor |
|---|---|
| Fim (exclusivo) | dia 1 do mês corrente, 00:00:00, horário de Brasília (UTC−3) |
| Início (inclusivo) | `QtdMesesCompletosCOI` meses antes do fim, mas **nunca antes** de `@PBI_InicioMinimoBR` |

Entram **só meses completos**: o mês em andamento fica de fora.
`@PBI_InicioMinimoBR` vale **01/03/2026**. Numa atualização feita em outubro de
2026, com 12 (ou 24) meses, o período vai de 01/03/2026 a 01/10/2026 — março a
setembro, sete meses, limitados pelo piso; com 3 meses, julho a setembro. A
cobertura cresce sozinha até a quantidade escolhida e depois anda mês a mês.

### Parâmetro `QtdMesesCompletosCOI`

A quantidade de meses é **um único parâmetro do Power Query**, usado pelas seis
consultas:

| Item | Valor |
|---|---|
| Nome | `QtdMesesCompletosCOI` |
| Tipo | número; aceito só inteiro positivo (1, 2, 3…) |
| Padrão | **12** |
| Onde mudar | Power BI Desktop: **Página Inicial › Transformar dados › Editar parâmetros**. Serviço: **Configurações do modelo semântico › Parâmetros** |
| Efeito | na próxima atualização, as seis consultas carregam os últimos N meses completos, nunca antes de 01/03/2026 |

**Parâmetro × filtro Mês/Ano.** O parâmetro define **quantos meses o modelo
carrega**; o filtro Mês/Ano de cada página escolhe **quais dos meses carregados**
o usuário vê. Mudar o filtro não lê o banco; mudar o parâmetro exige atualizar.

**Como o valor chega ao SQL.** Cada consulta do Power BI tem, no bloco
`[POWER BI] PERIODO AUTOMATICO`, a linha:

```sql
DECLARE @PBI_QuantidadeMeses int = 12;
```

O 12 é o valor para rodar o arquivo fora do Power BI (SSMS). No Power BI, a
função compartilhada `Executar consulta COI` (seção 7):

1. valida o parâmetro — se não for inteiro positivo, a atualização falha com a
   mensagem "QtdMesesCompletosCOI inválido";
2. troca essa linha, que precisa aparecer **uma única vez**, por
   `DECLARE @PBI_QuantidadeMeses int = @QtdMesesCompletosCOI;` — se não a
   encontrar, falha com "Consulta COI sem o marcador de período";
3. executa o lote com `Value.NativeQuery`, passando o valor como **parâmetro SQL
   tipado** (`sp_executesql`), e não concatenado ao texto.

O SQL também se protege: `@PBI_QuantidadeMeses` nulo ou menor que 1 interrompe
a consulta (`THROW 50001`), e o início é calculado de forma que valores muito
grandes resultam no piso, sem estouro de data. Nada das regras de Registrados,
Encerrados, responsáveis, tipos ou satisfação depende do parâmetro: ele só move
o início do período.

Conferido no SQL Server, executando as seis consultas exatamente como o Power
Query executa (texto trocado + parâmetro SQL), em 29/10/2026:

| Valor | Período | Resultado |
|---|---|---|
| 12 | mar–set/2026 | Registrados 25.727, Encerrados 4.036, pesquisas solicitadas 2.550, respondidas 2; Por Hora 168 linhas (24 por mês, sem repetição); totais iguais aos validados |
| 3 | jul–set/2026 | cada consulta devolve exatamente o recorte de julho a setembro do resultado com 12 (Registrados 10.800, Encerrados 1.625) |
| 0 | — | a consulta falha com a mensagem de valor inválido (conferido na consulta de Encerrados; o bloco é idêntico nas seis) |
| 2.147.483.647 | mar–set/2026 | igual a 12: limitado pelo piso, sem erro (idem) |

**Por que o piso.** Março de 2026 é o mês em que o novo COI passou a usar o
código de fornecedor atual, o grupo alvo de Encerrados `@COI_Novo` (seção 4), e
entra **inteiro**. Antes dele, os encerramentos do COI são do grupo antigo, de
outro contrato, que a regra não soma; sem o piso, o gráfico da Visão Geral
mostraria meses com Registrados e com Encerrados zerados — uma leitura errada.

**Março é mês de transição.** Os dois grupos encerraram chamados em março: o
grupo antigo até 24/03, `@COI_Novo` a partir de 08/03. O painel conta só
`@COI_Novo` — 478 encerramentos em março, 2 deles em 08/03 e 476 de 09/03 a
31/03, o período do relatório do fornecedor de março. Os encerramentos que
ficaram no grupo antigo são do contrato anterior e não entram, como em qualquer
mês. Registrados não depende do grupo alvo e conta março inteiro.

Para mudar a cobertura, mude só o parâmetro `QtdMesesCompletosCOI`; os seis
arquivos SQL não precisam ser editados. O piso só deve mudar junto com o grupo
alvo.

---

## 4. Grupo alvo de Encerrados

Encerrados identifica o COI por **um** grupo alvo, escolhido em
`@COI_GrupoAlvo`: `@COI_Novo` (fila `COI`) ou `@COI_Antigo` (fila antiga, hoje
`Contrato 7/2023 - COI`). Os dois são declarados em cada consulta que os usa.

| Consulta do Power BI | Grupo alvo |
|---|---|
| Encerrados | `@COI_Novo` — igual à referência |
| Registrados × Encerrados por hora | `@COI_Novo` — igual à referência |
| Registrados × Encerrados por membro | `@COI_Novo` — igual à referência |
| Satisfação, detalhe | `@COI_Novo` — igual à referência |
| Registrados × Encerrados por dia | `@COI_Novo` por padrão |

No **diário**, a referência vem com `@COI_Antigo`, preparada para conferência do
relatório de fevereiro de 2026. Ela própria indica `@COI_Novo` para produção, e
o período automático é sempre de produção; por isso a versão do Power BI usa
`@COI_Novo`. Para consultar o grupo anterior, troque a atribuição:

```sql
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Novo;     -- padrão do Power BI
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Antigo;   -- grupo anterior
```

Só a série `Encerrados` muda com essa troca; `Registrados` não usa o grupo alvo.
O grupo antigo não tem encerramentos depois de março de 2026: com ele, a série de
Encerrados fica vazia a partir de abril de 2026.

---

## 5. Colunas de diagnóstico do detalhe

O detalhe traz três colunas sobre grupos, com finalidades diferentes:

| Coluna | O que representa |
|---|---|
| `GrupoInit` | O valor informado em `%GROUP=` no evento de criação do chamado, normalizado. É informação auxiliar e pode não coincidir com o grupo em que o chamado nasceu |
| `PrimeiraOrigemGrupo` | O grupo de origem da primeira transferência de grupo legível do histórico. Quando há transferência, é a principal evidência de onde o chamado estava antes do primeiro movimento |
| `PrimeiroDestinoGrupo` | O grupo de destino dessa mesma primeira transferência. É a fila seguinte ao primeiro movimento, e não precisa ser o COI |

`GrupoInit` diferente de `PrimeiraOrigemGrupo` **não é erro**: o programa de
criação informou um valor e o chamado nasceu em outro grupo.
`InitConsistenteComReconstrucao` mostra essa comparação. As três colunas são de
diagnóstico; a entrada no indicador é decidida pela cadeia de transferências e
pelas demais regras de Registrados.

Exemplo: no SDM 1658863, `GrupoInit` é `VIRTUAL TI.ELABORAR/MANTER DOCUMENTAÇÃO`
— o nome de uma categoria, informado na criação —, `PrimeiraOrigemGrupo` é `COI`
e `PrimeiroDestinoGrupo` é `FORNECEDORES - VIRTUAL`. O chamado nasceu no COI e
entra no indicador como `ABERTO_NO_COI_CADEIA`, datado na abertura.

A descrição completa dessas colunas está na documentação de cálculo.

---

## 6. Montagem das páginas

O filtro **Mês/Ano** é o mesmo nas cinco páginas analíticas. Nas consultas de
detalhe ele sai da data do evento (`DataRegistroCOI` ou `Data de
Encerramento`); nas agregadas, de `Dia` ou de `Ano`/`Mes`/`MesAno`. O vínculo
entre as consultas (tabela de datas, relacionamentos e medidas) é feito no
modelo do Power BI.

| Página | Visual | Consulta | Como |
|---|---|---|---|
| Visão Geral | Cartão Registrados | detalhe de registrados | contagem de `SDM` |
| Visão Geral | Cartão Encerrados | encerrados | contagem de `SDM` |
| Visão Geral | Colunas agrupadas, Ano → Mês → Dia | diário | `Dia` na hierarquia; `Registrados` e `Encerrados` somados — cada nível é a soma dos dias |
| Visão Geral | Tabela Registrados | detalhe de registrados | uma linha por SDM: `SDM`, `DataRegistroCOI`, `Tipo`, `Categoria`, `RegistradorNome`, `Resumo`, `FormaRegistroCOI` |
| Visão Geral | Tabela Encerrados | encerrados | uma linha por SDM: `SDM`, `Data de Encerramento`, `Tipo Chamado`, `Símbolo`, `Status`, `Responsável`, `Resumo` |
| Por Hora | Gráfico Registrados ou Encerrados | Registrados × Encerrados por hora | `HoraLabel` no eixo; soma de `Registrados` ou soma de `Encerrados`, conforme a escolha da página |
| Por Hora | Tabela Hora × Registrados × Encerrados | Registrados × Encerrados por hora | `HoraLabel`, soma de `Registrados`, soma de `Encerrados`; as 24 horas vêm da consulta, inclusive com zero |
| Por Membro | Barras agrupadas e tabela | por membro | `Membro` no eixo; soma de `Registrados` e soma de `EncerradosComoResponsavel`, esta com o rótulo **Encerrados**; `TipoConta` para separar membros, pessoas fora do grupo e contas técnicas. A coluna `Encerrados` da consulta **não** entra nos visuais |
| Por Tipo | Registrados por tipo | detalhe de registrados | contagem de `SDM` por `Tipo` |
| Por Tipo | Encerrados por tipo | encerrados | contagem de `SDM` por `Tipo Chamado` |
| Satisfação | Cartão e tabela | satisfação, detalhe | ver abaixo |
| Documentação | HTML Content | nenhuma | o conteúdo de `powerbi/documentacao-powerbi-coi.html`, colado numa medida de texto |

**Por Membro segue o critério do fornecedor.** Os encerramentos de cada membro
são os de `EncerradosComoResponsavel`: cada chamado encerrado é atribuído ao seu
**responsável** (`call_req.assignee`), como na tabela por analista do relatório
do fornecedor e na coluna `Responsável` da consulta de encerrados. No painel, essa
coluna aparece com o rótulo **Encerrados**.

A consulta traz também a coluna `Encerrados`, que atribui o mesmo chamado a
**quem executou o encerramento** (regra em `docs/coi-calculation.md`). Ela fica
para auditoria e comparação e não alimenta o indicador. As duas colunas são duas
atribuições dos **mesmos** chamados: cada uma soma o total de Encerrados, e
**nunca** devem ser somadas entre si. Só a atribuição muda; a população de
Encerrados é a mesma em todas as consultas.

**Satisfação — o que contar.** A consulta tem uma linha por chamado encerrado, e
duas colunas respondem perguntas diferentes:

| Leitura | Filtro | Março a setembro de 2026 |
|---|---|---|
| Pesquisas **respondidas** — a regra do COI | `StatusSatisfacao` = `Com satisfação` | 2 |
| Pesquisas **solicitadas** pelo SDM | `PesquisaSolicitada` = `Sim` | 2.550 |
| Encerrados no período | todas as linhas | 4.036 |

O cartão "Quantidade de pesquisas" deve dizer qual das duas mostra; a regra
validada do COI é a de **respondidas**. A tabela de respostas é o conjunto com
`RespostaSatisfacao` preenchida.

---

## 7. Manutenção no Power Query

### Estrutura

| Consulta do Power Query | Papel | Carregada no modelo |
|---|---|---|
| `QtdMesesCompletosCOI` | parâmetro: quantos meses completos carregar (padrão 12) | não |
| `Executar consulta COI` | função compartilhada: valida o parâmetro, troca a linha do período e executa o SQL parametrizado | não |
| uma consulta por tabela (seis) | etapa `Sql` com o texto **inteiro** do arquivo de `powerbi/`, e etapa `Fonte` que chama a função | sim |

O texto SQL fica **dentro do relatório**, na etapa `Sql` de cada consulta — não
há leitura de arquivo `.sql` do disco, nem caminho local. Não é preciso mudar os
seis textos para mudar o período.

A função:

```powerquery
(TextoSql as text) as table =>
let
    Qtd = QtdMesesCompletosCOI,
    QtdValida =
        if Value.Is(Qtd, type number) and Qtd >= 1 and Qtd = Number.RoundDown(Qtd)
        then Int64.From(Qtd)
        else error Error.Record("QtdMesesCompletosCOI inválido",
            "Informe um número inteiro positivo de meses completos (por exemplo, 12).", Qtd),
    Marcador = "DECLARE @PBI_QuantidadeMeses int = 12;",
    Ocorrencias = List.Count(Text.PositionOf(TextoSql, Marcador, Occurrence.All)),
    TextoParametrizado =
        if Ocorrencias = 1
        then Text.Replace(TextoSql, Marcador, "DECLARE @PBI_QuantidadeMeses int = @QtdMesesCompletosCOI;")
        else error Error.Record("Consulta COI sem o marcador de período",
            "A linha " & Marcador & " deve aparecer uma única vez no SQL.", Ocorrencias),
    Fonte = Value.NativeQuery(
        Sql.Database("bdados-14r", "mdb"),
        TextoParametrizado,
        [QtdMesesCompletosCOI = QtdValida]),
    // Colunas binárias (UUIDs) não são carregáveis no modelo: viram texto hexadecimal.
    Binarias = List.Select(Table.ColumnNames(Fonte),
        (c) => Type.Is(Type.NonNullable(Type.TableColumn(Value.Type(Fonte), c)), type binary)),
    Resultado = Table.TransformColumns(Fonte,
        List.Transform(Binarias, (c) => {c, (b) => if b = null then null else Binary.ToText(b, BinaryEncoding.Hex), type nullable text}))
in
    Resultado
```

O parâmetro:

```powerquery
12 meta [IsParameterQuery = true, IsParameterQueryRequired = true, Type = "Number"]
```

Cada consulta de tabela:

```powerquery
let
    Sql = "USE mdb;#(lf)SET NOCOUNT ON;#(lf)...",   // o arquivo de powerbi/ inteiro
    Fonte = #"Executar consulta COI"(Sql)
in
    Fonte
```

A fonte de dados é fixa (`bdados-14r`, `mdb`), o que mantém a atualização
compatível com o gateway no Serviço; o parâmetro só altera o valor passado ao
SQL. Na primeira atualização depois de trocar um texto SQL, o Power BI Desktop
pede a aprovação da consulta nativa.

### Atualizar o SQL de uma consulta

**Página Inicial › Transformar dados** › selecione a consulta › etapa **Sql** ›
cole o arquivo de `powerbi/` **inteiro** no lugar do texto anterior (o editor
avançado mostra quebras de linha como `#(lf)`). **Fechar e aplicar**. A linha
`DECLARE @PBI_QuantidadeMeses int = 12;` precisa continuar no texto.

### Conexão

| Item | Valor |
|---|---|
| Conector | SQL Server, por `Value.NativeQuery` |
| Banco de dados | `mdb` |
| Modo | Importação |
| SQL | o arquivo inteiro, sem selecionar trecho |
| Parâmetro SQL | `@QtdMesesCompletosCOI` (int), vindo de `QtdMesesCompletosCOI` |

Cada consulta é somente leitura e roda num único lote. Cada atualização executa
a consulta inteira de novo e substitui os dados importados.

### Tempo de atualização

As consultas de Registrados (detalhe, diário, por hora e por membro) leem o
histórico de eventos de todos os chamados do período e levam de dois a quatro
minutos cada, para sete meses. As só de Encerrados (encerrados e satisfação)
levam segundos.

---

## 8. Conferência depois de atualizar

1. **Registrados fecham.** Linhas do detalhe de registrados = soma de
   `Registrados` do diário = soma de `Registrados` do por hora = soma de
   `Registrados` do por membro.
2. **Encerrados fecham.** Linhas de encerrados = soma de `Encerrados` do diário
   = soma de `Encerrados` do por hora = soma de `Encerrados` do por membro =
   soma de `EncerradosComoResponsavel` do por membro = linhas do detalhe de
   satisfação.
3. **Calendário completo.** Uma linha por dia no diário; 24 linhas por mês nas
   consulta por hora.
4. **Sem duplicidade.** Nos três detalhes, número de linhas = número de SDMs
   distintos; no por membro, uma linha por mês e conta.
5. **Tipos fecham.** Incidentes + Solicitações = total, em cada detalhe.
6. **Regra de Registrados.** Para o mesmo período, `queries/consulta_coi_registrados_validacao.sql`
   com as 16 asserções em `SIM`.

---

## 9. Limitações

- **Registrados e Encerrados não são o mesmo universo.** Registrado é a primeira
  entrada no COI; Encerrado é o fechamento no grupo alvo. `Registrados` menos
  `Encerrados` não é o estoque em aberto do COI.
- **Cobertura a partir de março de 2026.** O piso de período acompanha o grupo
  alvo de Encerrados (seção 3). Meses anteriores são do contrato antigo e ficam
  para as consultas de `queries/`, com `@COI_Antigo`. Em março, os
  encerramentos que ficaram no grupo antigo também ficam fora.
- **Membro do grupo COI é a composição de hoje.** `TipoConta` usa `grpmem`, que
  guarda os membros atuais dos dois grupos do COI. Quem saiu da equipe aparece
  como `Fora do grupo COI`, inclusive nos meses em que ainda era membro, assim
  como analistas que o relatório do fornecedor lista no COI e que não constam
  hoje de `grpmem`. Por isso `TipoConta` serve para ler a tabela, não para
  filtrar o indicador.
- **Quem registrou é quem abriu.** Registrados por membro usa `log_agent`; num
  chamado transferido para o COI, quem abriu é de outra fila e aparece como
  `Fora do grupo COI`. Os registros das automações aparecem como `Conta técnica
  / automação`.
- **Meses fechados podem mudar.** As consultas leem o estado atual da base; uma
  correção posterior num chamado muda o resultado de uma nova atualização.
- **Satisfação** quase nunca tem resposta nas filas do COI: o SDM registra o
  pedido de pesquisa, mas quase nenhum vira pesquisa respondida.

---

## 10. Alertas de manutenção

- **A regra vive nas consultas de referência.** As consultas do Power BI são o
  texto delas, com as adaptações deste documento marcadas no próprio SQL com
  `[POWER BI]`. Uma mudança de regra é feita na referência e replicada na versão
  do Power BI.
- **Bloco canônico de Registrados.** O trecho entre `INICIO` e `FIM REGRA
  CANONICA DE REGISTRADOS COI` é idêntico, byte a byte, nas nove consultas de
  Registrados de referência (as sete originais e as de Registrados × Encerrados
  por membro e por hora) e nas quatro do Power BI que o usam (detalhe, diário,
  por hora e por membro). A igualdade é conferida pelo SHA256 do trecho.
- **Bloco das contas técnicas.** O trecho `REGRA COMPARTILHADA TECNICOS COI` é
  idêntico nas duas consultas de contas técnicas de `queries/`. Nenhuma consulta
  do painel o usa.
- **Valores que não são parâmetros.** `@TransIniBR`, `@TransFimBR`, os UUIDs do
  COI, a lista de nomes do COI e a lista de filas do Task Scheduler descrevem
  fatos; não são ajustes de período.
- **Colunas.** Os nomes e a ordem das colunas são os da referência. Uma coluna
  nova na referência precisa entrar também na versão do Power BI.

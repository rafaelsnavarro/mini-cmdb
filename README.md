# Mini CMDB

Inventário de máquinas e softwares para redes Windows, feito em **PowerShell puro**. Ele coleta hardware e programas instalados de cada estação, confere o checklist de softwares padrão, registra o histórico de mudanças e gera um **painel HTML** que abre em qualquer navegador.

Não precisa de servidor, banco de dados nem instalar nada nas estações: basta uma pasta de rede.

![Visão geral](docs/visao-geral.png)

## Funcionalidades

- **Coleta automática**: fabricante, modelo, nº de série, CPU, RAM, discos (espaço livre, SSD/HDD), versão do Windows, último patch, IP/MAC, usuário logado e todos os softwares instalados.
- **Três formas de coletar**:
  - remota, a partir de uma máquina do TI (WinRM, em paralelo);
  - por **GPO**, com cada máquina se coletando sozinha (não precisa de WinRM);
  - local, rodando na própria máquina.
- **Checklist de softwares padrão** com % de conformidade, e lista de **softwares proibidos**.
- **Histórico de mudanças**: software instalado, removido ou atualizado, troca de RAM, disco, SO, nº de série e usuário.
- **Pontos de atenção**: disco quase cheio, Windows sem atualização há mais de 45 dias, máquinas sem coleta, softwares proibidos.
- **Painel autônomo**, com busca, filtros, detalhes por máquina, exportação para CSV/Excel e tema claro/escuro.

| Máquinas | Detalhe da máquina |
|---|---|
| ![Máquinas](docs/maquinas.png) | ![Detalhe](docs/detalhe.png) |

Veja um exemplo interativo, com dados fictícios, em [`docs/painel-exemplo.html`](docs/painel-exemplo.html). Baixe o arquivo e abra no navegador.

## Requisitos

- Windows 10/11 com **Windows PowerShell 5.1** (já vem no Windows) ou PowerShell 7.
- Para a coleta remota: WinRM habilitado nas estações e uma conta de administrador local.
- Para a coleta por GPO: Active Directory e uma pasta de rede com permissão de escrita para "Computadores do domínio".

## Início rápido

1. Baixe o repositório (**Code > Download ZIP**) e **extraia** a pasta.
2. Copie `maquinas.exemplo.csv` para `maquinas.csv` e preencha com as suas máquinas. A coluna `Ativo` é o nome da máquina na rede.
3. Ajuste os softwares padrão e proibidos em `config.json`.
4. Rode a coleta de uma destas formas:
   - `Coletar-Uma-Maquina.bat`: pergunta o nome da máquina. Deixe em branco para coletar a própria máquina.
   - `Coletar.bat`: coleta todas as máquinas do `maquinas.csv` remotamente.
5. Abra o `painel.html` gerado.

O passo a passo completo (WinRM, GPO, agendamento, permissões) está no [`LEIA-ME.txt`](LEIA-ME.txt).

## Estrutura

```
Coletar-Inventario.ps1   Coleta (parâmetros: -ComputerName, -Credential, -Local, -Gpo, -SemPainel)
Gerar-Painel.ps1         Gera o painel.html a partir dos dados coletados
Coletar.bat              Atalho: coleta todas as máquinas
Coletar-Uma-Maquina.bat  Atalho: coleta uma máquina específica
Gerar-Painel.bat         Atalho: só atualiza o painel
config.json              Softwares padrão e proibidos (expressões regulares)
maquinas.exemplo.csv     Modelo do cadastro manual
lib/                     Funções comuns e template do painel
dados/                   (gerada) coletas, histórico e log; ignorada pelo git
```

## Configuração dos softwares

Cada item do `config.json` usa uma expressão regular comparada com o nome do programa em "Aplicativos instalados", sem diferenciar maiúsculas e minúsculas:

```json
{ "Nome": "Adobe Reader", "Padrao": "Adobe Acrobat|Adobe Reader", "Obrigatorio": true }
```

`|` significa "ou" e `^` significa "começa com". Itens com `"Obrigatorio": false` aparecem no painel, mas não contam na conformidade.

## Privacidade

O `.gitignore` já impede que `dados/`, `painel.html` e `maquinas.csv` sejam enviados ao repositório. **Nunca faça commit desses arquivos**: eles contêm nomes de máquinas, usuários, números de série e IPs.

## Limitações

- Programas portáteis (executados sem instalar) não aparecem.
- Programas instalados só para um usuário aparecem apenas se esse usuário estiver logado na hora da coleta.

<p align="center"><img src="logo.png" alt="my-debian-setup" width="96"></p>

# my-debian-setup

Transforma um Debian 13 com XFCE recém-instalado num ambiente no estilo [Omarchy](https://omarchy.org): i3 como gerenciador de janelas, barra e menus feitos em Quickshell, temas que mudam o sistema inteiro de uma vez e atalhos de teclado para tudo.

É o meu ambiente de trabalho, com as minhas personalizações: o tema **QuielRed** (grafite com vermelho carmim), a fonte **0xProto Nerd Font**, o logo do Debian no menu e várias correções.

## Instalação

Num **Debian 13 (amd64)** com XFCE recém-instalado e conectado à internet, abra o terminal e rode:

```sh
sudo apt install -y git
git clone https://github.com/ezequieljc/my-debian-setup.git
cd my-debian-setup && ./instalar.sh
```

No final, o instalador pergunta se pode reiniciar. Depois de reiniciar, a sessão **i3** já vem selecionada na tela de login e o tema é aplicado sozinho no primeiro acesso.

Se durante a instalação do Debian você definiu uma senha de root, seu usuário ainda não pode usar o `sudo`. Libere uma vez com o comando abaixo (ele pede a senha de root), saia da sessão, entre de novo e siga os passos acima:

```sh
su -c "/usr/sbin/adduser $USER sudo"
```

## Atualizar

Dentro da pasta do repositório:

```sh
git pull && ./instalar.sh
```

O instalador pode ser executado quantas vezes quiser. Ele mantém o layout da barra que você tiver ajustado nas configurações.

#!/bin/bash
# Instala o my-debian-setup (tema QuielRed) num Debian 13 com XFCE recém-instalado.
#
#   ./instalar.sh
#
# Roda como usuário comum; pede a senha do sudo uma vez para instalar pacotes.
# Pode ser executado de novo para atualizar a partir do repositório.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -t 1 ]; then
	bold=$'\e[1m'; red=$'\e[31m'; green=$'\e[32m'; yellow=$'\e[33m'; reset=$'\e[0m'
else
	bold=""; red=""; green=""; yellow=""; reset=""
fi
step() { echo; echo "${bold}==> $*${reset}"; }
warn() { echo "${yellow}aviso:${reset} $*"; }
die()  { echo "${red}erro:${reset} $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "rode como seu usuário, sem sudo:  ./instalar.sh"
command -v sudo >/dev/null || die "o sudo não está instalado. Rode: su -c \"apt install sudo && /usr/sbin/adduser $USER sudo\""

. /etc/os-release
if [ "${ID:-}" != debian ] || [ "${VERSION_ID:-}" != 13 ]; then
	warn "feito e testado para Debian 13; este sistema é ${PRETTY_NAME:-desconhecido}."
	read -r -p "Continuar mesmo assim? [s/N] " answer </dev/tty
	[[ "$answer" =~ ^[sSyY] ]] || exit 1
fi
if [ "$(dpkg --print-architecture)" != amd64 ]; then
	warn "o Quickshell incluído é só para amd64; a barra não vai abrir neste sistema."
fi

echo "${bold}Instalando o my-debian-setup para $USER${reset}"
sudo -v || die "não foi possível obter permissão de administrador."

step "1/5  Pacotes do sistema"
sudo "$REPO_DIR/setup.sh"

step "2/5  Temas e comandos do Omarchy"
"$REPO_DIR/install.sh"

step "3/5  Configurações (i3, barra, terminal, fontes)"
"$REPO_DIR/deploy.sh"
fc-cache -f >/dev/null 2>&1 || true

step "4/5  canivt (gerenciador de arquivos no terminal)"
# Vem do repositório próprio; sem acesso ao GitHub, o resto da instalação segue.
canivt_tmp=$(mktemp -d)
if git clone -q --depth 1 https://github.com/ezequieljc/canivt.git "$canivt_tmp/canivt" &&
	"$canivt_tmp/canivt/install.sh" --no-deps; then
	echo ":: canivt instalado (atalho: Super + E)"
else
	warn "não foi possível instalar o canivt agora; rode o instalar.sh de novo mais tarde."
fi
rm -rf "$canivt_tmp"

step "5/5  Ajustes finais"
# xfce4-terminal: sem barra de menu, copiar ao selecionar, fechar sem perguntar.
term_settings=(
	"/misc-menubar-default false"
	"/misc-copy-on-select true"
	"/misc-confirm-close false"
)
if command -v xfconf-query >/dev/null && xfconf-query -c xfce4-terminal -l >/dev/null 2>&1; then
	for s in "${term_settings[@]}"; do
		read -r prop value <<<"$s"
		xfconf-query -c xfce4-terminal -p "$prop" -n -t bool -s "$value"
	done
else
	xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
	if [ ! -f "$xml" ]; then
		mkdir -p "$(dirname "$xml")"
		{
			echo '<?xml version="1.1" encoding="UTF-8"?>'
			echo '<channel name="xfce4-terminal" version="1.0">'
			for s in "${term_settings[@]}"; do
				read -r prop value <<<"$s"
				echo "  <property name=\"${prop#/}\" type=\"bool\" value=\"$value\"/>"
			done
			echo '</channel>'
		} >"$xml"
	fi
fi
echo ":: xfce4-terminal configurado"

# Sessão i3 como padrão na tela de login (LightDM lê o AccountsService ou ~/.dmrc).
printf '[Desktop]\nSession=i3\n' >"$HOME/.dmrc"
if command -v busctl >/dev/null && busctl status org.freedesktop.Accounts >/dev/null 2>&1; then
	sudo busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
		org.freedesktop.Accounts.User SetXSession s i3 >/dev/null 2>&1 || true
fi
echo ":: sessão i3 definida como padrão"

echo
echo "${green}${bold}Pronto!${reset} Depois de reiniciar, a sessão ${bold}i3${reset} já vem selecionada na"
echo "tela de login e o tema QuielRed é aplicado no primeiro acesso."
echo
answer=n
if { exec 3</dev/tty; } 2>/dev/null; then
	read -r -u 3 -p "Reiniciar o computador agora? [S/n] " answer || answer=n
	exec 3<&-
fi
if [[ -z "$answer" || "$answer" =~ ^[sSyY] ]]; then
	sudo systemctl reboot
else
	echo "Reinicie quando quiser para usar o novo ambiente."
fi

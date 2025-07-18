#!/bin/bash

# ==============================================================================
# Script para Instalação e Configuração de Servidor iPXE no Debian 12
#
# Autor: Paulo/Esc Suporte
# Versão: 1.5 - Download automático do Memtest86+
#
# Descrição:
# Este script automatiza a instalação de um servidor de boot via rede (PXE/iPXE)
# para carregar instaladores do Windows, um ambiente Ubuntu Live e diversas
# ferramentas de manutenção baseadas em WinPE.
# Utiliza: isc-dhcp-server, tftpd-hpa, nginx, samba, ipxe e wimboot.
#
# Pré-requisitos:
#   - Executar como root ou com privilégios de sudo.
#   - Uma instalação limpa do Debian 12.
#   - O servidor deve ter um endereço IP estático configurado.
#   - Imagens ISO das ferramentas e sistemas operacionais desejados.
# ==============================================================================

# --- Verificação de Root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado como root. Use 'sudo ./nome_do_script.sh'"
  exit 1
fi

# --- Variáveis de Configuração (Personalize se necessário) ---

# Tenta detectar a interface de rede principal e o IP do servidor automaticamente
SERVER_INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
SERVER_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1 | cut -d'/' -f1 | cut -d'.' -f1-3)

# Configurações da Rede DHCP
DHCP_SUBNET="${SUBNET}.0"
DHCP_NETMASK="255.255.255.0"
DHCP_RANGE_START="${SUBNET}.150"
DHCP_RANGE_END="${SUBNET}.200"
DHCP_ROUTER="${SUBNET}.1"
DHCP_DNS="8.8.8.8, 8.8.4.4" # Ex: Google DNS

# Caminhos de diretórios
TFTP_ROOT="/srv/tftp"
WEB_ROOT="/var/www/html"
IPXE_WEB_DIR="${WEB_ROOT}/ipxe"
# Sistemas Operacionais
WIN10_FILES_DIR="${IPXE_WEB_DIR}/win10"
WIN11_FILES_DIR="${IPXE_WEB_DIR}/win11"
UBUNTU_LIVE_DIR="${IPXE_WEB_DIR}/ubuntu-live"
# Ferramentas de Manutenção
HIRENS_DIR="${IPXE_WEB_DIR}/hirens"
MINITOOL_DIR="${IPXE_WEB_DIR}/minitool"
ACTIVEBOOT_DIR="${IPXE_WEB_DIR}/activeboot"
AOMEI_DIR="${IPXE_WEB_DIR}/aomei"
MEMTEST_DIR="${IPXE_WEB_DIR}/memtest"

# --- Funções Auxiliares ---
print_info() {
  echo -e "\n\e[1;34m[INFO]\e[0m $1"
}

print_success() {
  echo -e "\e[1;32m[SUCESSO]\e[0m $1"
}

print_error() {
  echo -e "\e[1;31m[ERRO]\e[0m $1"
  exit 1
}

# --- Início da Instalação ---

clear
print_info "Iniciando a instalação do servidor iPXE com Ferramentas de Manutenção..."
echo "--------------------------------------------------"
echo "IP do Servidor detectado: ${SERVER_IP}"
echo "Interface de Rede detectada: ${SERVER_INTERFACE}"
echo "Sub-rede DHCP: ${DHCP_SUBNET} com máscara ${DHCP_NETMASK}"
echo "Range de IPs: ${DHCP_RANGE_START} a ${DHCP_RANGE_END}"
echo "--------------------------------------------------"
read -p "As configurações acima estão corretas? (s/N) " confirm
if [[ ! "$confirm" =~ ^[sS]$ ]]; then
  echo "Instalação cancelada. Por favor, edite as variáveis no início do script."
  exit 0
fi

# 1. Atualização do Sistema e Instalação de Pacotes
print_info "Atualizando o sistema e instalando pacotes necessários..."
apt-get update >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
apt-get install -y isc-dhcp-server tftpd-hpa nginx ipxe wget samba || print_error "Falha ao instalar pacotes."
print_success "Pacotes instalados."

# 2. Configuração do Servidor DHCP (isc-dhcp-server)
print_info "Configurando o servidor DHCP..."
DHCP_CONFIG_FILE="/etc/dhcp/dhcpd.conf"
cp "$DHCP_CONFIG_FILE" "${DHCP_CONFIG_FILE}.bak"
cat > "$DHCP_CONFIG_FILE" <<EOF
option domain-name "local.lan";
option domain-name-servers ${DHCP_DNS};
default-lease-time 600;
max-lease-time 7200;
authoritative;
log-facility local7;
subnet ${DHCP_SUBNET} netmask ${DHCP_NETMASK} {
  range ${DHCP_RANGE_START} ${DHCP_RANGE_END};
  option broadcast-address ${SUBNET}.255;
  option routers ${DHCP_ROUTER};
  next-server ${SERVER_IP};
  if exists user-class and option user-class = "iPXE" {
    filename "http://${SERVER_IP}/ipxe/menu.ipxe";
  } else {
    filename "undionly.kpxe";
  }
}
EOF
sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"${SERVER_INTERFACE}\"/" /etc/default/isc-dhcp-server
print_success "Servidor DHCP configurado."

# 3. Configuração do Servidor TFTP (tftpd-hpa)
print_info "Configurando o servidor TFTP..."
TFTP_CONFIG_FILE="/etc/default/tftpd-hpa"
sed -i "s|TFTP_DIRECTORY=\".*\"|TFTP_DIRECTORY=\"${TFTP_ROOT}\"|" "$TFTP_CONFIG_FILE"
sed -i "s/TFTP_OPTIONS=\".*\"/TFTP_OPTIONS=\"--secure --create\"/" "$TFTP_CONFIG_FILE"
mkdir -p "$TFTP_ROOT"
cp /usr/lib/ipxe/undionly.kpxe "$TFTP_ROOT/"
cp /usr/lib/ipxe/ipxe.efi "$TFTP_ROOT/"
print_success "Servidor TFTP configurado."

# 4. Configuração do Servidor Web (Nginx), Samba e Menu iPXE
print_info "Configurando Nginx, Samba e criando o menu iPXE..."
# Cria todos os diretórios necessários
mkdir -p "$IPXE_WEB_DIR" "$WIN10_FILES_DIR" "$WIN11_FILES_DIR" "$UBUNTU_LIVE_DIR"
mkdir -p "$HIRENS_DIR" "$MINITOOL_DIR" "$ACTIVEBOOT_DIR" "$AOMEI_DIR" "$MEMTEST_DIR"

# 4.1 Baixar wimboot
WIMBOOT_URL="https://github.com/ipxe/wimboot/releases/latest/download/wimboot"
print_info "Baixando wimboot..."
wget -q "$WIMBOOT_URL" -O "${IPXE_WEB_DIR}/wimboot" || print_error "Falha ao baixar wimboot."
print_success "wimboot baixado com sucesso."

# 4.2 Baixar Memtest86+
MEMTEST_URL="https://www.memtest.org/download/v7.00/mt86plus_7.00_64.bin"
print_info "Baixando a versão mais recente do Memtest86+..."
wget -q "$MEMTEST_URL" -O "${MEMTEST_DIR}/memtest.bin" || print_error "Falha ao baixar Memtest86+."
print_success "Memtest86+ baixado com sucesso."

# 4.3 Configurar Samba para compartilhar os arquivos de instalação
print_info "Configurando o compartilhamento Samba..."
SAMBA_CONFIG_FILE="/etc/samba/smb.conf"
cp "$SAMBA_CONFIG_FILE" "${SAMBA_CONFIG_FILE}.bak"
cat >> "$SAMBA_CONFIG_FILE" <<EOF

[install]
    comment = Fontes de Instalação de SO e Ferramentas
    path = ${IPXE_WEB_DIR}
    browseable = yes
    read only = yes
    guest ok = yes
EOF
print_success "Compartilhamento Samba 'install' configurado para ${IPXE_WEB_DIR}."

# 4.4 Criar o script de menu principal do iPXE
IPXE_MENU_FILE="${IPXE_WEB_DIR}/menu.ipxe"
cat > "$IPXE_MENU_FILE" <<EOF
#!ipxe

# --- Script de Menu iPXE ---
menu iPXE Boot Menu (Servidor: ${SERVER_IP})

item --gap --             -------------------- Instaladores de SO --------------------
item win11install        Instalar Windows 11
item win10install        Instalar Windows 10
item ubuntulive          Carregar Ubuntu Live
item --gap --             ------------------- Ferramentas de Manutenção -------------------
item hirens              Carregar Hiren's BootCD PE
item minitool            Carregar MiniTool Partition Wizard
item activeboot          Carregar Active@ Boot Disk
item aomei               Carregar AOMEI Backupper
item memtest             Executar Memtest86+
item --gap --             ------------------------- Opções ---------------------------
item shell               Entrar no Shell do iPXE
item reboot              Reiniciar o computador
item exit                 Sair do iPXE e dar boot local

choose --default win11install --timeout 10000 target && goto \${target}

:win11install
echo Carregando instalador do Windows 11...
kernel http://${SERVER_IP}/ipxe/wimboot
initrd http://${SERVER_IP}/ipxe/win11/boot/bcd         BCD
initrd http://${SERVER_IP}/ipxe/win11/boot/boot.sdi    boot.sdi
initrd http://${SERVER_IP}/ipxe/win11/sources/boot.wim boot.wim
boot || goto failed

:win10install
echo Carregando instalador do Windows 10...
kernel http://${SERVER_IP}/ipxe/wimboot
initrd http://${SERVER_IP}/ipxe/win10/boot/bcd         BCD
initrd http://${SERVER_IP}/ipxe/win10/boot/boot.sdi    boot.sdi
initrd http://${SERVER_IP}/ipxe/win10/sources/boot.wim boot.wim
boot || goto failed

:ubuntulive
echo Carregando Ubuntu Live...
kernel http://${SERVER_IP}/ipxe/ubuntu-live/casper/vmlinuz boot=casper ip=dhcp fetch=http://${SERVER_IP}/ipxe/ubuntu-live/casper/filesystem.squashfs quiet splash --
initrd http://${SERVER_IP}/ipxe/ubuntu-live/casper/initrd
boot || goto failed

:hirens
echo Carregando Hiren's BootCD PE...
kernel http://${SERVER_IP}/ipxe/wimboot
initrd http://${SERVER_IP}/ipxe/hirens/boot/bcd         BCD
initrd http://${SERVER_IP}/ipxe/hirens/boot/boot.sdi    boot.sdi
initrd http://${SERVER_IP}/ipxe/hirens/sources/boot.wim boot.wim
boot || goto failed

:minitool
echo Carregando MiniTool Partition Wizard...
kernel http://${SERVER_IP}/ipxe/wimboot
initrd http://${SERVER_IP}/ipxe/minitool/boot/bcd         BCD
initrd http://${SERVER_IP}/ipxe/minitool/boot/boot.sdi    boot.sdi
initrd http://${SERVER_IP}/ipxe/minitool/sources/boot.wim boot.wim
boot || goto failed

:activeboot
echo Carregando Active@ Boot Disk...
kernel http://${SERVER_IP}/ipxe/wimboot
initrd http://${SERVER_IP}/ipxe/activeboot/boot/bcd         BCD
initrd http://${SERVER_IP}/ipxe/activeboot/boot/boot.sdi    boot.sdi
initrd http://${SERVER_IP}/ipxe/activeboot/sources/boot.wim boot.wim
boot || goto failed

:aomei
echo Carregando AOMEI Backupper...
kernel http://${SERVER_IP}/ipxe/wimboot
initrd http://${SERVER_IP}/ipxe/aomei/boot/bcd         BCD
initrd http://${SERVER_IP}/ipxe/aomei/boot/boot.sdi    boot.sdi
initrd http://${SERVER_IP}/ipxe/aomei/sources/boot.wim boot.wim
boot || goto failed

:memtest
echo Carregando Memtest86+...
kernel http://${SERVER_IP}/ipxe/memtest/memtest.bin
boot || goto failed

:shell
shell
goto reboot

:reboot
reboot

:exit
exit

:failed
echo Falha ao carregar o boot. Pressione qualquer tecla para reiniciar.
sleep 5
reboot
EOF
print_success "Menu iPXE criado em ${IPXE_MENU_FILE}"

# 5. Reiniciar os Serviços
print_info "Reiniciando e habilitando os serviços..."
systemctl restart isc-dhcp-server || print_error "Falha ao reiniciar o serviço DHCP."
systemctl restart tftpd-hpa || print_error "Falha ao reiniciar o serviço TFTP."
systemctl restart nginx || print_error "Falha ao reiniciar o serviço Nginx."
systemctl restart smbd nmbd || print_error "Falha ao reiniciar os serviços do Samba."

systemctl enable isc-dhcp-server
systemctl enable tftpd-hpa
systemctl enable nginx
systemctl enable smbd nmbd

print_success "Serviços reiniciados e habilitados na inicialização."

# --- Fim da Instalação ---
echo
print_success "Instalação do servidor iPXE concluída!"
echo "---------------------------------------------------------------------"
echo -e "\e[1;33m[AÇÃO NECESSÁRIA]\e[0m Para as opções de boot funcionarem, copie os arquivos das ISOs:"
echo ""
echo -e "\e[1;32mPara o INSTALADOR DO WINDOWS 11:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/windows11.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${WIN11_FILES_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo -e "\e[1;32mPara o INSTALADOR DO WINDOWS 10:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/windows10.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${WIN10_FILES_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo -e "\e[1;32mPara o UBUNTU LIVE:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/ubuntu-live.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${UBUNTU_LIVE_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo -e "\e[1;32mPara o HIREN'S BOOTCD PE:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/Hiren's.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${HIRENS_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo -e "\e[1;32mPara o MINITOOL PARTITION WIZARD:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/MiniTool.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${MINITOOL_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo -e "\e[1;32mPara o ACTIVE@ BOOT DISK:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/ActiveBoot.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${ACTIVEBOOT_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo -e "\e[1;32mPara o AOMEI BACKUPPER:\e[0m"
echo "1. Monte a ISO: sudo mount -o loop /caminho/para/Aomei.iso /mnt"
echo "2. Copie os arquivos: sudo cp -r /mnt/* ${AOMEI_DIR}/"
echo "3. Desmonte a ISO: sudo umount /mnt"
echo ""
echo "NOTA: A estrutura de arquivos dentro das ISOs de ferramentas pode variar."
echo "O script assume a estrutura padrão (boot/bcd, boot/boot.sdi, sources/boot.wim)."
echo "Se uma ferramenta não funcionar, verifique os caminhos dentro da ISO e ajuste o menu.ipxe."
echo "---------------------------------------------------------------------"

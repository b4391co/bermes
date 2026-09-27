#!/bin/sh
# Sube un sshd de TEST (puerto 2222, root) cuyo PATH no-interactivo NO incluye
# ~/.local/bin, con un `herdr` simulado dentro — reproduce el caso real reportado.
set -e
D=/tmp/herdr_ssh
mkdir -p $D/home/.local/bin $D/home/.ssh
[ -f $D/id_test ] || ssh-keygen -t ed25519 -f $D/id_test -N "" -q
[ -f $D/host_ed25519 ] || ssh-keygen -t ed25519 -f $D/host_ed25519 -N "" -q
cat $D/id_test.pub > $D/home/.ssh/authorized_keys
cat > $D/home/.local/bin/herdr <<'H'
#!/bin/sh
case "$1 $2" in
  "session snapshot") echo '{"sessions":[{"id":"s1","name":"demo","status":"idle","agent":"claude"}]}';;
  "--version" ) echo "herdr 0.9.1";;
  *) echo '{}';;
esac
H
chmod 755 $D/home/.local/bin/herdr
cat > $D/sshd_config <<CFG
Port 2222
HostKey $D/host_ed25519
PidFile $D/sshd.pid
StrictModes no
UsePAM no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile $D/home/.ssh/authorized_keys
PermitRootLogin yes
AllowTcpForwarding no
CFG
/usr/sbin/sshd -f $D/sshd_config -E $D/sshd.log
echo "sshd de test en 2222 (pem: $D/id_test)"

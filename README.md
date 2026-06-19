# paleo-geo-ansible

Ansible playbook + Docker Compose setup that deploys two sites
for the Paleo Earth research group at Utrecht University:

- a **WordPress site** (Apache + PHP + MariaDB) at `www.paleo.test`
- a **static site** (Apache only, no PHP/database) at `static.paleo.test`

Each site runs as its own Docker Compose stack bound to its own IP on the
same VM (192.168.70.10 and 192.168.70.11), so both use standard port 443
with no reverse proxy.

This is the **MVP** of a reusable base. The pattern is borrowed from
[`UtrechtUniversity/matomo-ansible`](https://github.com/UtrechtUniversity/matomo-ansible),
adapted to a LAMP + WordPress stack.

## Running it

### Development (Vagrant on Linux host)

```bash
# 1. Bring up the VM
vagrant up

# 2. Deploy
ansible-playbook playbook.yml

# 3. Add to /etc/hosts
echo "192.168.70.10 www.paleo.test"    | sudo tee -a /etc/hosts
echo "192.168.70.11 static.paleo.test" | sudo tee -a /etc/hosts

# 4. Browse to https://www.paleo.test and https://static.paleo.test
```

### Production

Not defined yet, to be added.

## Backup & restore

A systemd timer backs up each site weekly (see `paleo_backup`). Backups land in
`/home/paleo/paleo-backups/<site>/` on the VM. Restore is disaster recovery on the **same host**.

```bash
# On-demand backup
ansible-playbook backup.yml -e site=wordpress      # or -e site=static

# List backups on the VM
vagrant ssh -c 'sudo ls -t /home/paleo/paleo-backups/wordpress/'

# Restore a backup
ansible-playbook restore.yml -e site=wordpress \
  -e backup=/home/paleo/paleo-backups/wordpress/<file>.tar.gz
```

## Volume & mount paths

Named Docker volumes stay under `/var/lib/docker/volumes/<name>/_data` on the VM.

### WordPress site

| Volume / mount | VM path | Container path |
| --- | --- | --- |
| `paleo_wp_html` (named) | `/var/lib/docker/volumes/paleo_wp_html/_data` | `/var/www/html` |
| `paleo_wp_db_data` (named) | `/var/lib/docker/volumes/paleo_wp_db_data/_data` | `/var/lib/mysql` |
| `paleo_wp_apache_certs` (named) | `/var/lib/docker/volumes/paleo_wp_apache_certs/_data` | `/etc/apache2/certs` |
| `import-certificates/` (bind) | `/home/paleo/paleo-ansible/docker/wordpress/import-certificates/` | `/etc/import-certificates` |

### Static site

| Volume / mount | VM path | Container path |
| --- | --- | --- |
| `paleo_static_html` (named) | `/var/lib/docker/volumes/paleo_static_html/_data` | `/var/www/html` |
| `paleo_static_apache_certs` (named) | `/var/lib/docker/volumes/paleo_static_apache_certs/_data` | `/etc/apache2/certs` |

### License

This project is licensed under the **GNU General Public License v3.0**.
See the [LICENSE](LICENSE) file for the full text.

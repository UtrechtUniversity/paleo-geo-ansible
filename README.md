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

## Design notes

To be added.

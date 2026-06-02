# paleo-ansible

Ansible playbook + Docker Compose setup that deploys a Dockerised LAMP stack
hosting WordPress sites for the Paleo Earth research group at Utrecht University.

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
echo "192.168.70.10 www.paleo.test" | sudo tee -a /etc/hosts

# 4. Browse to https://www.paleo.test  
```

### Production

Not defined yet, to be added.

## Design notes

To be added.

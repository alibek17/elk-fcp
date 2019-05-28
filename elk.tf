provider "aws" {
  region = "${var.region}"
}

resource "aws_instance" "elk" {
  instance_type               = "${var.instance_type}"
  ami                         = "${var.ami}"
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  security_groups             = ["allow_ssh_and_elk"]

  provisioner "file" {
    source      = "elasticsearch.repo"
    destination = "/tmp/elasticsearch.repo"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
  }

  provisioner "remote-exec" {
    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }

    inline = [
        "sudo yum install java-1.8.0-openjdk -y",
        "sudo yum install epel-release -y",
        "sudo mv /tmp/elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo",
        "sudo yum install certbot-nginx -y"
        "sudo yum install nginx -y",
        "sudo systemctl start nginx",
        "sudo certbot --nginx -d elk.${var.domain} -n --agree-tos --email ${var.email}",
        "sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048",
        "sudo systemctl reload nginx",
        "sudo echo '15 3 * * * /usr/bin/certbot renew --quiet' > /var/spool/root"
        "sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch"
    ]
  }

  provisioner "file" {
    source      = "elasticsearch.yml"
    destination = "/tmp/elasticsearch.yml"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
  }
  provisioner "remote-exec" {
    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }

    inline = [
        "sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch",
        "sudo yum install elasticsearch -y",
        "sudo mv /tmp/elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo",
        "sudo mv /tmp/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml",
        "sudo systemctl start elasticsearch",
        "sudo systemctl enable elasticsearch",
        "sudo yum install kibana -y",
        "sudo systemctl enable kibana -y",
        "sudo systemctl start kibana -y",
        "sudo echo kibanaadmin:`openssl passwd -apr1 '${password}'` | sudo tee -a /etc/nginx/htpasswd.users"
        "sudo cat <<EOF > /etc/nginx/conf.d/${var.domain}.conf
                server {
                    listen 80;

                    server_name ${var.domain}m;

                    auth_basic 'Restricted Access';
                    auth_basic_user_file /etc/nginx/htpasswd.users;

                    location / {
                        proxy_pass http://localhost:5601;
                        proxy_http_version 1.1;
                        proxy_set_header Upgrade $http_upgrade;
                        proxy_set_header Connection 'upgrade';
                        proxy_set_header Host $host;
                        proxy_cache_bypass $http_upgrade;
                    }

                    listen 443 ssl; # managed by Certbot
                    ssl_certificate /etc/letsencrypt/live/fuchiyama.com/fullchain.pem; # managed by Certbot
                    ssl_certificate_key /etc/letsencrypt/live/fuchiyama.com/privkey.pem; # managed by Certbot
                    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
                    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
                }

                EOF",
        "sudo systemctl restart nginx",
        "sudo systemctl restart kibana",
        "sudo setsebool httpd_can_network_connect 1 -P",
        "sudo yum install logstash -y"

    ]
  }

  # logstash 02 file 
  provisioner "file" {
    source      = "02-beats-input.conf"
    destination = "/tmp/02-beats-input.conf"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
  }
  
  # logstash 10 file 
  provisioner "file" {
    source      = "10-syslog-filter.conf"
    destination = "/tmp/10-syslog-filter.conf"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
  }
  
  
  # logstash 30 file 
  provisioner "file" {
    source      = "30-elasticsearch-output.conf"
    destination = "/tmp/30-elasticsearch-output.conf"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
  }

  provisioner "remote-exec" {
    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
  }
    inline = [
      "sudo mv /tmp/02-beats-input.conf /etc/logstash/conf.d",
      "sudo mv /tmp/10-syslog-filter.conf /etc/logstash/conf.d",
      "sudo mv /tmp/30-elasticsearch-output.conf /etc/logstash/conf.d",
      "sudo systemctl start logstash",
      "sudo systemctl enable logstash",
      "sudo yum install filebeat"
    ]
  }

  provisioner "file" {
    source      = "filebeat.yaml"
    destination = "/tmp/filebeat.yaml"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
  }
  provisioner "remote-exec" {
    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
  }
    inline = [
      "sudo mv /tmp/filebeat.yaml /etc/filebeat/filebeat.yml",
      "sudo filebeat modules enable system",
      "sudo filebeat setup --template -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200']",
      "sudo filebeat setup -e -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200'] -E setup.kibana.host=localhost:5601",
      "sudo systemctl start filebeat",
      "sudo systemctl enable filebeat"
    ]
  }

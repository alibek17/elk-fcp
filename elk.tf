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
  provisioner "file" {
    source      = "nginx_dom.conf"
    destination = "/tmp/elk.${var.domain}.conf"

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "${var.user}"
      private_key = "${file(var.ssh_key_location)}"
    }
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
        "sudo yum install java-1.8.0-openjdk -y",
        "sudo yum install epel-release -y",
        "sudo yum install nginx -y",
        "sudo systemctl start nginx",
        "sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch",
        "sudo mv /tmp/elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo",
        "sudo yum install elasticsearch -y",
        "sudo sed -i '/#network.host/ c network.host: localhost' /etc/elasticsearch/elasticsearch.yml",
        "sudo systemctl start elasticsearch",
        "sudo systemctl enable elasticsearch",
        "sudo yum install kibana -y",
        "sudo systemctl enable kibana",
        "sudo systemctl start kibana",
        "sudo echo kibanaadmin:`openssl passwd -apr1 '${var.password}'` | sudo tee -a /etc/nginx/htpasswd.users",
        "sudo mv /tmp/elk.${var.domain}.conf /etc/nginx/conf.d/elk.${var.domain}.conf",
        "sudo sed -i 's/tobereplaced/elk.${var.domain}/g' /etc/nginx/conf.d/elk.${var.domain}.conf",
        "sudo systemctl restart nginx",
        "sudo setsebool httpd_can_network_connect 1 -P",
        "sudo yum install logstash -y",
        "sudo mv /tmp/02-beats-input.conf /etc/logstash/conf.d",
        "sudo mv /tmp/10-syslog-filter.conf /etc/logstash/conf.d",
        "sudo mv /tmp/30-elasticsearch-output.conf /etc/logstash/conf.d",
        "sudo systemctl start logstash",
        "sudo systemctl enable logstash",
        "sudo yum install filebeat -y",
        "sudo sed -i 's/output.elasticsearch/#output.elasticsearch/g' /etc/filebeat/filebeat.yml",
        "sudo sed -i '/9200/ c \\ \\ #hosts: [\"localhost:9200\"]' /etc/filebeat/filebeat.yml",
        "sudo sed -i 's/#output.logstash/output.logstash/g' /etc/filebeat/filebeat.yml",
        "sudo sed -i '/5044/ c \\ \\ hosts: [\"localhost:5044\"]' /etc/filebeat/filebeat.yml",
        "sudo filebeat modules enable system",
        "sudo filebeat setup --template -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200']",
        "sudo filebeat setup -e -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200'] -E setup.kibana.host=localhost:5601",
        "sudo systemctl start filebeat",
        "sudo systemctl enable filebeat",
    ]
  }
  tags = {
      Name = "Elk"
    }
}
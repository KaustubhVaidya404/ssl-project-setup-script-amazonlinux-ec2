#!/bin/bash

# Update package list and install necessary packages
echo "Updating package list and installing prerequisites..."
sudo yum update -y
sudo yum install -y curl gnupg

# Install Nginx
echo "Installing Nginx..."
sudo yum install -y nginx

# Set up SSL certificates using Certbot (assumes domain is set up)
echo "Installing Certbot and obtaining SSL certificate..."
sudo yum install -y certbot python3-certbot-nginx
read -p "Enter your domain name: " DOMAIN_NAME
sudo certbot --nginx -d $DOMAIN_NAME

# Replace Nginx configuration file with the new content
NGINX_CONF_PATH="/etc/nginx/conf.d/$DOMAIN_NAME.conf"

echo "Updating Nginx configuration at $NGINX_CONF_PATH..."
sudo bash -c "cat > $NGINX_CONF_PATH" <<EOL
# HTTP Server to HTTPS Server
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS Server Block: Handle Secure Connections
server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    error_page 404 /404.html;
    location = /404.html {
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
    }
}
EOL

# Reload Nginx to apply changes
echo "Reloading Nginx..."
sudo systemctl reload nginx

# Install Node.js
echo "Installing Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Install PM2 globally
echo "Installing PM2..."
sudo npm install -g pm2

# Install and configure CloudWatch Agent
echo "Installing CloudWatch Agent..."
sudo yum install -y amazon-cloudwatch-agent

echo "Configuring CloudWatch Agent..."
read -p "Enter your domain name: " LOG_GROUP_NAME
sudo certbot --nginx -d $LOG_GROUP_NAME 
# Example configuration (you may need to adjust the configuration file path)
cat <<EOF | sudo tee /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
        "agent": {
                "metrics_collection_interval": 60,
                "run_as_user": "root"
        },
        "logs": {
                "logs_collected": {
                        "files": {
                                "collect_list": [
                                        {
                                                "file_path": "/var/log/messages",
                                                "log_group_class": "STANDARD",
                                                "log_group_name": $LOG_GROUP_NAME,
                                                "log_stream_name": "{instance_id}",
                                                "retention_in_days": 1
                                        },
                                        {
                                                "file_path": "/repo/monorepo/unified-bot/build",
                                                "log_group_class": "STANDARD",
                                                "log_group_name": "eclogsofunifiedbotv1",
                                                "log_stream_name": "{instance_id}",
                                                "retention_in_days": 1
                                        }
                                ]
                        }
                }
        },
        "metrics": {
                "aggregation_dimensions": [
                        [
                                "InstanceId"
                        ]
                ],
                "append_dimensions": {
                        "AutoScalingGroupName": "${aws:AutoScalingGroupName}",
                        "ImageId": "${aws:ImageId}",
                        "InstanceId": "${aws:InstanceId}",
                        "InstanceType": "${aws:InstanceType}"
                },
                "metrics_collected": {
                        "cpu": {
                                "measurement": [
                                        "cpu_usage_idle",
                                        "cpu_usage_iowait",
                                        "cpu_usage_user",
                                        "cpu_usage_system"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ],
                                "totalcpu": false
                        },
                        "disk": {
                                "measurement": [
                                        "used_percent",
                                        "inodes_free"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ]
                        },
                        "diskio": {
                                "measurement": [
                                        "io_time"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ]
                        },
                        "mem": {
                                "measurement": [
                                        "mem_used_percent"
                                ],
                                "metrics_collection_interval": 60
                        },
                        "statsd": {
                                "metrics_aggregation_interval": 60,
                                "metrics_collection_interval": 10,
                                "service_address": ":8125"
                        },
                        "swap": {
                                "measurement": [
                                        "swap_used_percent"
                                ],
                                "metrics_collection_interval": 60
                        }
                }
        }
}
EOF

echo "Starting CloudWatch Agent..."
sudo systemctl start amazon-cloudwatch-agent

npm install

rm -rf ./build

npm run prepare

# Run project using PM2
echo "Starting project with PM2..."
cd /home/ec2-user/monorepo/unified-bot/

# Prompt user for ENVIRONMENT value
read -p "Enter ENVIRONMENT value (default is 'prod'): " ENVIRONMENT_INPUT

# Set ENVIRONMENT to the user input or default to 'prod'
ENVIRONMENT=${ENVIRONMENT_INPUT:-prod}

# Prompt user for AWS_REGION value
read -p "Enter AWS_REGION value (default is 'eu-west-1'): " AWS_REGION_INPUT

# Set AWS_REGION to the user input or default to 'eu-west-1'
AWS_REGION=${AWS_REGION_INPUT:-eu-west-1}

# Update ecosystem.config.js with new values
sed -i "s/ENVIRONMENT: '.*'/ENVIRONMENT: '$ENVIRONMENT'/g" ecosystem.config.js
sed -i "s/AWS_REGION: '.*'/AWS_REGION: '$AWS_REGION'/g" ecosystem.config.js

pm2 start ecosystem.config.js

echo "Setup complete!"


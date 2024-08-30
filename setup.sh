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
# Example configuration (you may need to adjust the configuration file path)
cat <<EOF | sudo tee /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "disk_io_time"
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

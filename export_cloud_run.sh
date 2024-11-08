#!/bin/bash
# export_cloud_run.sh
# This script exports Cloud Run configuration and generates initial Terraform code

set -e  # Exit on error

# Check and install dependencies
check_dependencies() {
    echo "Checking and installing dependencies..."
    
    # Install yq if not present
    if ! command -v yq &> /dev/null; then
        echo "Installing yq..."
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
        sudo chmod +x /usr/bin/yq
    fi
}

# Enable required APIs
enable_apis() {
    echo "Enabling required APIs..."
    gcloud services enable run.googleapis.com
    gcloud services enable secretmanager.googleapis.com
    gcloud services enable vpcaccess.googleapis.com
}

# Set variables
set_variables() {
    echo "Setting up variables..."
    PROJECT_ID=$(gcloud config get-value project)
    REGION=$(gcloud config get-value compute/region)
    
    # If region is not set, default to us-central1
    if [ -z "$REGION" ]; then
        REGION="us-central1"
        gcloud config set compute/region $REGION
    fi
    
    echo "Using project: $PROJECT_ID"
    echo "Using region: $REGION"
    
    OUTPUT_DIR="terraform_export"
    mkdir -p "$OUTPUT_DIR"
}

# Export Cloud Run services
export_cloud_run() {
    echo "Exporting Cloud Run services..."
    
    # Get list of all services without filtering
    gcloud run services list \
        --format="table(name,region)" > "$OUTPUT_DIR/services.txt"
    
    # Skip the header line when processing
    tail -n +2 "$OUTPUT_DIR/services.txt" | while read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        SERVICE_NAME=$(echo "$line" | awk '{print $1}')
        SERVICE_REGION=$(echo "$line" | awk '{print $2}')
        
        if [ -z "$SERVICE_NAME" ] || [ -z "$SERVICE_REGION" ]; then continue; fi
        
        echo "Exporting config for service: $SERVICE_NAME in region: $SERVICE_REGION"
        
        # Export service configuration
        gcloud run services describe "$SERVICE_NAME" \
            --region="$SERVICE_REGION" \
            --format=yaml > "$OUTPUT_DIR/${SERVICE_NAME}_config.yaml"
        
        # Export IAM policies
        gcloud run services get-iam-policy "$SERVICE_NAME" \
            --region="$SERVICE_REGION" \
            --format=yaml > "$OUTPUT_DIR/${SERVICE_NAME}_iam.yaml"
        
        # Extract and export service account details if exists
        if [ -f "$OUTPUT_DIR/${SERVICE_NAME}_config.yaml" ]; then
            SA_EMAIL=$(yq '.spec.template.serviceAccount' "$OUTPUT_DIR/${SERVICE_NAME}_config.yaml")
            if [ "$SA_EMAIL" != "null" ] && [ -n "$SA_EMAIL" ]; then
                gcloud iam service-accounts describe "$SA_EMAIL" \
                    --format=yaml > "$OUTPUT_DIR/${SERVICE_NAME}_sa.yaml" || true
            fi
        fi
    done
}

# Export VPC connectors
export_vpc() {
    echo "Exporting VPC connector configurations..."
    if [ -n "$REGION" ]; then
        gcloud compute networks vpc-access connectors list \
            --region="$REGION" \
            --format=yaml > "$OUTPUT_DIR/vpc_connectors.yaml" || true
    fi
}

# Export secrets (names only)
export_secrets() {
    echo "Exporting Secret Manager references..."
    gcloud secrets list \
        --format=yaml > "$OUTPUT_DIR/secrets.yaml" || true
}

# Generate Terraform files
generate_terraform_files() {
    echo "Generating Terraform configuration files..."
    
    # Generate main.tf
    cat > "$OUTPUT_DIR/main.tf" << 'EOL'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
EOL

    # Generate variables.tf
    cat > "$OUTPUT_DIR/variables.tf" << EOL
variable "project_id" {
  description = "The GCP project ID"
  default     = "${PROJECT_ID}"
}

variable "region" {
  description = "The GCP region"
  default     = "${REGION}"
}
EOL

    # Generate terraform.tfvars
    cat > "$OUTPUT_DIR/terraform.tfvars" << EOL
project_id = "${PROJECT_ID}"
region     = "${REGION}"
EOL
}

# Main execution
main() {
    echo "Starting Cloud Run configuration export..."
    
    check_dependencies
    enable_apis
    set_variables
    export_cloud_run
    export_vpc
    export_secrets
    generate_terraform_files
    
    echo "Export completed. Configuration files are in the $OUTPUT_DIR directory"
}

# Run the script
main

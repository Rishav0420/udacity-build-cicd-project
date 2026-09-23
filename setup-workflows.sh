#!/bin/bash
set -e
cd /workspace/.github/workflows

# Remove the empty and wrong-extension files
rm -f backend-cd.yml backend-ci.yml frontend-cd.yml frontend-ci.yml

# Create frontend-ci.yaml
cat > frontend-ci.yaml << 'EOF'
name: Frontend Continuous Integration

on:
  pull_request:
    branches: [ main ]
    paths:
      - 'starter/frontend/**'
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/frontend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup NodeJS
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './starter/frontend/package-lock.json'
      - name: Install dependencies
        run: npm ci
      - name: Run linter
        run: npm run lint

  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/frontend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup NodeJS
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './starter/frontend/package-lock.json'
      - name: Install dependencies
        run: npm ci
      - name: Run tests
        run: CI=true npm test

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    defaults:
      run:
        working-directory: ./starter/frontend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Build Docker image
        run: |
          docker build \
            --build-arg=REACT_APP_MOVIE_API_URL=http://localhost:5000 \
            --tag=mp-frontend:latest \
            .
EOF

# Create backend-ci.yaml
cat > backend-ci.yaml << 'EOF'
name: Backend Continuous Integration

on:
  pull_request:
    branches: [ main ]
    paths:
      - 'starter/backend/**'
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/backend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install pipenv
        run: pip install pipenv
      - name: Install dependencies
        run: pipenv install --dev
      - name: Run linter
        run: pipenv run lint

  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/backend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install pipenv
        run: pip install pipenv
      - name: Install dependencies
        run: pipenv install --dev
      - name: Run tests
        run: pipenv run test

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    defaults:
      run:
        working-directory: ./starter/backend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build --tag mp-backend:latest .
EOF

# Create frontend-cd.yaml
cat > frontend-cd.yaml << 'EOF'
name: Frontend Continuous Deployment

on:
  push:
    branches: [ main ]
    paths:
      - 'starter/frontend/**'
  workflow_dispatch:

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: frontend
  CLUSTER_NAME: cluster

jobs:
  lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/frontend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup NodeJS
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './starter/frontend/package-lock.json'
      - name: Install dependencies
        run: npm ci
      - name: Run linter
        run: npm run lint

  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/frontend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup NodeJS
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './starter/frontend/package-lock.json'
      - name: Install dependencies
        run: npm ci
      - name: Run tests
        run: CI=true npm test

  build-and-push:
    runs-on: ubuntu-latest
    needs: [lint, test]
    outputs:
      registry: \${{ steps.login-ecr.outputs.registry }}
    defaults:
      run:
        working-directory: ./starter/frontend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup NodeJS
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './starter/frontend/package-lock.json'
      - name: Install dependencies
        run: npm ci
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: \${{ env.AWS_REGION }}
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2
      - name: Build and push
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: \${{ github.sha }}
        run: |
          docker build \
            --build-arg=REACT_APP_MOVIE_API_URL=\${{ secrets.BACKEND_API_URL }} \
            --tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \
            .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG

  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Install kubectl
        uses: azure/setup-kubectl@v4
      - name: Install kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          sudo mv kustomize /usr/local/bin/
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: \${{ env.AWS_REGION }}
      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name \${{ env.CLUSTER_NAME }} --region \${{ env.AWS_REGION }}
      - name: Deploy
        working-directory: ./starter/frontend/k8s
        env:
          ECR_REGISTRY: \${{ needs.build-and-push.outputs.registry }}
          IMAGE_TAG: \${{ github.sha }}
        run: |
          kustomize edit set image frontend=\$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          kustomize build | kubectl apply -f -
EOF

# Create backend-cd.yaml
cat > backend-cd.yaml << 'EOF'
name: Backend Continuous Deployment

on:
  push:
    branches: [ main ]
    paths:
      - 'starter/backend/**'
  workflow_dispatch:

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: backend
  CLUSTER_NAME: cluster

jobs:
  lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/backend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install pipenv
        run: pip install pipenv
      - name: Install dependencies
        run: pipenv install --dev
      - name: Run linter
        run: pipenv run lint

  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./starter/backend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install pipenv
        run: pip install pipenv
      - name: Install dependencies
        run: pipenv install --dev
      - name: Run tests
        run: pipenv run test

  build-and-push:
    runs-on: ubuntu-latest
    needs: [lint, test]
    outputs:
      registry: \${{ steps.login-ecr.outputs.registry }}
    defaults:
      run:
        working-directory: ./starter/backend
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: \${{ env.AWS_REGION }}
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2
      - name: Build and push
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: \${{ github.sha }}
        run: |
          docker build --tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG

  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Install kubectl
        uses: azure/setup-kubectl@v4
      - name: Install kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          sudo mv kustomize /usr/local/bin/
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: \${{ env.AWS_REGION }}
      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name \${{ env.CLUSTER_NAME }} --region \${{ env.AWS_REGION }}
      - name: Deploy
        working-directory: ./starter/backend/k8s
        env:
          ECR_REGISTRY: \${{ needs.build-and-push.outputs.registry }}
          IMAGE_TAG: \${{ github.sha }}
        run: |
          kustomize edit set image backend=\$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          kustomize build | kubectl apply -f -
EOF

echo "=== Files created ==="
ls -la
echo ""
echo "=== Verifying ==="
head -5 frontend-ci.yaml
echo "..."
head -5 backend-ci.yaml
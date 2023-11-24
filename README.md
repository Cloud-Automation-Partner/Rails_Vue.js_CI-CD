# Continuous Integration and Deployment (CI/CD) for Rails and Vue.js Project  

  
This documentation outlines the setup for Continuous Integration (CI) and Continuous Deployment (CD) processes for a project   
that utilizes Ruby on Rails for the backend and Vue.js for the frontend. The CI/CD pipelines are configured using GitHub shared runners.  


## Overview
- **CI Phase**: Involves running test cases and linting the code.
- **CD Phase**: Focuses on building Docker images from the source code for the production environment, pushing these images to Docker Hub, and deploying them to AWS EC2 instances.
  
## Trigger Mechanism  

- The pipeline is triggered by pull requests (PRs) as direct pushes to the production branch are restricted.  
- CI/CD processes start only after the PR is merged into the branch.   

## Setup Steps
  
### 1. Rails Backend Repository
#### Step 1: Configure Continuous Integration (CI) 

- In the Rails repository, go to .github/workflows.
- Create a file named rails-ci.yml.
- Add the following YAML configuration:

```yaml
name: "Ruby on Rails CI"
on:
  pull_request:
    branches:
      - master
    types:
      - closed
  workflow_dispatch:
env:
  RUBY_VERSION: 3.0
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:11-alpine
        ports:
          - "5432:5432"
        env:
          POSTGRES_DB: rails_test
          POSTGRES_USER: rails
          POSTGRES_PASSWORD: password
    env:
      RAILS_ENV: test
      DATABASE_URL: "postgres://rails:password@localhost:5432/rails_test"
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      # Add or replace dependency steps here
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ env.RUBY_VERSION }}
      - name: Install Ruby and gems
        uses: ruby/setup-ruby@55283cc23133118229fd3f97f9336ee23a179fcf # v1.146.0
        with:
          bundler-cache: true
      # Add or replace database setup steps here
      - name: Set up database schema
        run: bin/rails db:schema:load
      # Add or replace test runners here
      - name: Run tests
        run: bin/rake

  lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ env.RUBY_VERSION }} #Change this to your Ruby version
          
      - name: Install Ruby and gems
        uses: ruby/setup-ruby@55283cc23133118229fd3f97f9336ee23a179fcf # v1.146.0
        with:
          bundler-cache: true
      - name: Security audit dependencies
        run: bin/bundler-audit --update
      - name: Install Bundler
        run: gem install bundler
      - name: Install Dependencies
        run: bundle install
      - name: Install Brakeman
        run: gem install brakeman rubocop rubocop-rails rubocop-rspec
      - name: Security audit application code
        run: brakeman --no-exit-on-warn 
      - name: Lint Ruby files
        run: rubocop --parallel

  check-status:
    needs: [test, lint]
    runs-on: ubuntu-latest
    steps:
      - name: Check test and lint status
        run: echo "Both test and lint jobs were successful."

```
This script sets up the environment, runs tests, and performs linting.

#### Step 2: Configure Continuous Deployment (CD)  

- Create a file named rails-cd.yml.
- Add the following YAML configuration for deploying to AWS EC2:

```yaml
name: Build & Push Docker Images

on:
  workflow_run:
    workflows: ["Ruby on Rails CI"]
    types:
      - completed
    branches:
      - master
  workflow_dispatch:
env:
  RUBY_VERSION: 3.0

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'success'
    env:
      DB_USERNAME: ${{ secrets.DB_USERNAME }}
      DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
      DB_HOST: ${{ vars.DB_HOST }}
      SIDEKIQ_USERNAME: ${{ secrets.SIDEKIQ_USERNAME }}
      SIDEKIQ_PASSWORD: ${{ secrets.SIDEKIQ_PASSWORD }}
      SECRET_KEY_BASE: ${{ secrets.SECRET_KEY_BASED }}
      SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
      SERVER_USER: ${{ secrets.SERVER_USER }}
      SERVER_IP: ${{ secrets.SERVER_IP }}
      FRONTEND_URL: ${{ secrets.FRONTEND_URL }}
      GMAIL_USERNAME: ${{ secrets.GMAIL_USERNAME }}
      GMAIL_PASSWORD: ${{ secrets.GMAIL_PASSWORD }}


    steps:
      - name: Checkout Repository
        uses: actions/checkout@v2

      - name: Create .env File
        run: |
          echo "DB_USERNAME=${{ secrets.DB_USERNAME }}" > .env
          echo "DB_PASSWORD=${{ secrets.DB_PASSWORD }}" >> .env
          echo "DB_HOST=${{ vars.DB_HOST }}" >> .env
          echo "SIDEKIQ_USERNAME=${{ secrets.SIDEKIQ_USERNAME }}" >> .env
          echo "SIDEKIQ_PASSWORD=${{ secrets.SIDEKIQ_PASSWORD }}" >> .env
          echo "SECRET_KEY_BASE=${{ secrets.SECRET_KEY_BASE }}" >> .env
          echo "FRONTEND_URL=${{ secrets.FRONTEND_URL }}" >> .env
          echo "GMAIL_USERNAME=${{ secrets.GMAIL_USERNAME }}" >> .env
          echo "GMAIL_PASSWORD=${{ secrets.GMAIL_PASSWORD }}" >> .env


      - name: Build Docker Images
        run: docker-compose -f docker-compose.production.yml build

      - name: Tag Docker Images
        run: |
          docker tag timebot-be_web:latest docker_hub/timebot-be:web
          docker tag timebot-be_sidekiq:latest docker_hub/timebot-be:sidekiq

      - name: Push Docker Images to Docker Hub
        run: |
          echo ${{ secrets.DOCKERHUB_TOKEN }} | docker login -u ${{ secrets.DOCKERHUB_USERNAME }} --password-stdin
          docker push docker_hub/timebot-be:web
          docker push docker_hub/timebot-be:sidekiq
      
      - name: Deploy to Server
        run: |
          mkdir -p /home/runner/.ssh
          printf "%s" "${{ secrets.SSH_PRIVATE_KEY }}" > /home/runner/.ssh/id_ed25519
          chmod 700 /home/runner/.ssh
          chmod 600 /home/runner/.ssh/id_ed25519
          SERVER_PATH=/root/
          chmod +x ./.github/workflows/rails.sh
          ssh -Tv -i /home/runner/.ssh/id_ed25519 -o StrictHostKeyChecking=no $SERVER_USER@$SERVER_IP 'bash -s' < ./.github/workflows/rails.sh
        shell: bash
        env: # ensure these are set in your secrets or environment variables
          SERVER_USER: ${{ secrets.SERVER_USER }}
          SERVER_IP: ${{ secrets.SERVER_IP }}
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
```
This script builds and pushes Docker images, and deploys to the server.

#### Step 3: Deployment Script

- Create a file named rails.sh.

This script is executed on the production server after CD completion:

```bash
#! /bin/bash
          
cd /root/
docker-compose -f docker-compose.server.yml pull
docker-compose -f docker-compose.server.yml up -d
docker ps -a
docker-compose -f docker-compose.server.yml run web rails db:migrate
docker-compose -f docker-compose.server.yml run web rails db:seed
```
#### Step 4: Add Secret Variables  

- Navigate to "Settings" > "Secrets" in your GitHub repository.
- Add necessary secret variables as per your project requirements.
  In our case below secret variables were added
  
      DB_USERNAME:
      DB_PASSWORD:
      DB_HOST:
      SIDEKIQ_USERNAME:
      SIDEKIQ_PASSWORD:
      SECRET_KEY_BASE:
      SSH_PRIVATE_KEY:
      SERVER_USER:
      SERVER_IP:
      FRONTEND_URL:
  

#### Step 5: Commit and Push Changes  

- Commit the files to your main branch and push them to GitHub.
  
### 2. Vue.js Frontend Repository  

#### Step 1: Configure Continuous Integration (CI)  

- In the Vue.js repository, navigate to .github/workflows.
- Create a file named vue-ci.yml.
- Add the following YAML content:

```yaml
name: Docker Image CI

on:
  push:
    branches:
      - master
  pull_request:
    branches:
      - master
    types:
      - closed
  workflow_dispatch:

jobs:
  build-and-push:

    runs-on: ubuntu-latest

    env:
      SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
      SERVER_USER: ${{ secrets.SERVER_USER }}
      SERVER_IP: ${{ secrets.SERVER_IP }}
      
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v2

      - name: Build the Docker image
        run: docker build . --file Dockerfile -t timebot-fe:latest

      - name: Tag Docker Image
        run: |
          docker tag timebot-fe:latest docker_hub/timebot-be:frontend
      - name: Push Docker Image to Docker Hub
        run: |
          echo ${{ secrets.DOCKERHUB_TOKEN }} | docker login -u ${{ secrets.DOCKERHUB_USERNAME }} --password-stdin
          docker push docker_hub/timebot-be:frontend

      - name: Deploy to Server
        run: |
          mkdir -p /home/runner/.ssh
          printf "%s" "${{ secrets.SSH_PRIVATE_KEY }}" > /home/runner/.ssh/id_ed25519
          chmod 700 /home/runner/.ssh
          chmod 600 /home/runner/.ssh/id_ed25519
          SERVER_PATH=/root/
          ssh -Tv -i /home/runner/.ssh/id_ed25519 -o StrictHostKeyChecking=no $SERVER_USER@$SERVER_IP "cd $SERVER_PATH && docker-compose -f docker-compose.server.yml pull && docker-compose -f docker-compose.server.yml up -d"
        shell: bash
        env: # ensure these are set in your secrets or environment variables
          SERVER_USER: ${{ secrets.SERVER_USER }}
          SERVER_IP: ${{ secrets.SERVER_IP }}
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
```

#### Step 2: Add Secret Variables 

- Similar to the Rails setup, add required secret variables in the GitHub repository.
  
### Step 3: Commit and Push Changes    

- Commit and push the changes to your main branch.
 
### 3. Testing CI/CD  

- After pushing changes, check the "Actions" tab in your GitHub repositories.  
- Monitor workflows for successful execution or any errors.
  
This Document provides a clear, professional, and easy-to-follow guide for setting up CI/CD for a Rails and Vue.js project using GitHub Actions and deploying to AWS EC2.

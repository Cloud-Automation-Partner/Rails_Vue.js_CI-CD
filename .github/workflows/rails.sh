#! /bin/bash
          
cd /root/
docker-compose -f docker-compose.server.yml pull
docker-compose -f docker-compose.server.yml up -d
docker ps -a
docker-compose -f docker-compose.server.yml run web rails db:migrate
docker-compose -f docker-compose.server.yml run web rails db:seed

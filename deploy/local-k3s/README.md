# Driving School как тестовая SIMODO-работа для k3s

Эта директория относится только к приложению `driving-school`.

Общая инфраструктура кластера лежит отдельно:

```text
../simodo-labs-infra/local-k3s
```

Здесь остаются только файлы, которые нужны конкретной работе:

```text
Dockerfile
run-simodo.sh
app.yaml
gitlab-ci.yml
```

## Имена

```text
WORK_NAME=driving-school
Kubernetes namespace=driving-school
Deployment=driving-school
Public URL prefix=/driving-school
Registry image=registry.local:5050/simodo-labs/driving-school
```

## Подготовка Инфраструктуры

Из директории `../simodo-labs-infra/local-k3s`:

```sh
make gitlab-up
make k3s-registry-config
make k3s-local-dns
make runner-install RUNNER_TOKEN=<runner-token>
make work-namespace WORK_NAME=driving-school
make registry-secret WORK_NAME=driving-school REGISTRY_USER=<user> REGISTRY_PASSWORD=<password>
```

## Проверка Приложения

После CI-деплоя:

```sh
curl -fsS http://labs.local/driving-school/students
curl -fsS http://labs.local/driving-school/training-plans
curl -fsS http://labs.local/driving-school/exam-applications
```

Traefik снимает prefix `/driving-school`, поэтому внутри SIMODO запрос приходит как `/students`, `/training-plans`, `/exam-applications`.


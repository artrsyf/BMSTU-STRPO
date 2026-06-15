# Локальный стенд SIMODO: GitLab CE + GitLab Runner + k3s

Этот документ описывает полное развертывание локального прототипа платформы
для студенческих SIMODO-работ.

Итоговая цепочка:

```text
Git push
  -> self-hosted GitLab CE
  -> GitLab Runner с Kubernetes Executor
  -> временный CI Pod
  -> Kaniko собирает OCI image
  -> image публикуется в GitLab Container Registry
  -> deploy job применяет Kubernetes-манифесты
  -> приложение запускается в namespace работы
  -> smoke job проверяет приложение через Traefik
```

Основной сценарий ниже использует явные команды. Makefile является только
короткой оберткой над ними.

## 1. Структура Каталогов

```text
strpo/
  simodo-labs-infra/
    local-k3s/                 общая инфраструктура
      docker-compose.yml       GitLab CE и Container Registry
      runner-values.yaml       GitLab Runner с Kubernetes Executor
      registries.yaml          настройка registry для containerd/k3s
      templates/               namespace и RBAC
      Makefile                 сокращения команд

  drivingschool/
    deploy/local-k3s/          файлы конкретной тестовой работы
      Dockerfile
      run-simodo.sh
      app.yaml
      gitlab-ci.yml
```

Инфраструктура не содержит логики `driving-school`. Проект работы не содержит
конфигурацию GitLab CE, Runner и общих namespace-шаблонов.

## 2. Компоненты Стенда

```text
Windows / Docker Desktop:
  GitLab CE
  GitLab Container Registry

WSL Ubuntu:
  systemd
  k3s
  containerd
  kubectl
  Helm

k3s:
  kube-system:
    CoreDNS
    Traefik
    local-path-provisioner
    metrics-server

  gitlab-runner:
    GitLab Runner
    временные Pod для CI jobs

  driving-school:
    Deployment приложения
    Services
    Ingress
    ResourceQuota
    LimitRange
    RBAC
```

## 3. Предварительные Требования

Нужны:

```text
Windows 10/11
WSL2 с Ubuntu
Docker Desktop
Git
доступ в интернет для загрузки k3s, Helm и OCI images
```

Docker Desktop используется только для GitLab CE. Сам k3s использует
встроенный `containerd`, поэтому Docker Engine внутри Ubuntu не требуется.

Интеграцию Docker Desktop с Ubuntu лучше отключить:

```text
Docker Desktop
-> Settings
-> Resources
-> WSL Integration
-> Ubuntu: Off
```

Это предотвращает появление некорректных mount-записей в WSL, из-за которых
kubelet может завершаться с ошибкой:

```text
system validation failed - wrong number of fields
```

## 4. Systemd И cgroup v2

В `/etc/wsl.conf` внутри Ubuntu должно быть:

```ini
[boot]
systemd=true
```

В Windows-файле `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
kernelCommandLine=cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1
```

После изменения выполнить в PowerShell:

```powershell
wsl --shutdown
```

После повторного запуска Ubuntu проверить:

```sh
systemctl is-system-running
stat -fc %T /sys/fs/cgroup
mount | grep cgroup
```

Ожидается:

```text
cgroup2fs
cgroup2 on /sys/fs/cgroup type cgroup2
```

Hybrid-режим с `/sys/fs/cgroup/unified` и отдельными cgroup v1 контроллерами
для новых версий kubelet не подходит.

## 5. Установка k3s

В WSL:

```sh
curl -sfL https://get.k3s.io | sh -
```

Проверить:

```sh
sudo systemctl status k3s --no-pager -l
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

Нода должна перейти в состояние `Ready`.

## 6. Отдельный kubeconfig Для Локального k3s

Существующий `~/.kube/config` перетирать не нужно.

```sh
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/k3s.yaml
sudo chown "$USER:$USER" ~/.kube/k3s.yaml
chmod 600 ~/.kube/k3s.yaml
```

Проверка:

```sh
KUBECONFIG="$HOME/.kube/k3s.yaml" kubectl get nodes
```

Удобный alias:

```sh
echo 'alias k3s-kubectl="KUBECONFIG=$HOME/.kube/k3s.yaml kubectl"' >> ~/.bashrc
source ~/.bashrc
```

Теперь:

```sh
k3s-kubectl get nodes
k3s-kubectl get pods -A
k3s-kubectl config get-contexts
```

## 7. Установка Helm

В WSL:

```sh
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
  -o /tmp/get-helm-3.sh
chmod +x /tmp/get-helm-3.sh
/tmp/get-helm-3.sh
helm version
```

Helm используется для установки GitLab Runner в k3s.

## 8. Запуск GitLab CE

GitLab запускается через Docker Desktop. В PowerShell:

```powershell
cd C:\Users\artrsyf\Desktop\uni\strpo\simodo-labs-infra\local-k3s
docker compose up -d
docker compose ps
```

Эквивалент: [`gitlab-up`](./Makefile#L40).

GitLab использует Docker named volumes. Нельзя монтировать его данные в
`/mnt/c`: GitLab выполняет Linux-операции `chown` и `chgrp`, которые не
поддерживаются Windows DrvFS в требуемом виде.

Проверить готовность:

```powershell
docker inspect --format='Status={{.State.Status}} Health={{.State.Health.Status}} RestartCount={{.RestartCount}}' simodo-local-gitlab
docker exec simodo-local-gitlab gitlab-ctl status
curl.exe -I http://localhost:8929/users/sign_in
```

Ожидается:

```text
Status=running
Health=healthy
HTTP 200 или 302
```

Получить начальный пароль:

```powershell
docker exec simodo-local-gitlab cat /etc/gitlab/initial_root_password
```

Эквивалент: [`gitlab-password`](./Makefile#L50).

Вход:

```text
URL:      http://gitlab.local:8929
Username: root
Password: initial_root_password
```

После входа пароль root нужно заменить.

## 9. Локальные DNS-Имена В WSL

GitLab и Registry работают в Docker Desktop на Windows. Получить адрес
Windows-хоста:

```sh
WINDOWS_HOST_IP="$(ip route show default | awk 'NR == 1 {print $3}')"
echo "$WINDOWS_HOST_IP"
```

Обновить `/etc/hosts`, предварительно удалив старые записи:

```sh
sudo sed -i '/[[:space:]]gitlab\.local\([[:space:]]\|$\)/d' /etc/hosts
sudo sed -i '/[[:space:]]registry\.local\([[:space:]]\|$\)/d' /etc/hosts
sudo sed -i '/[[:space:]]labs\.local\([[:space:]]\|$\)/d' /etc/hosts

printf '%s gitlab.local registry.local\n' "$WINDOWS_HOST_IP" | sudo tee -a /etc/hosts
printf '127.0.0.1 labs.local\n' | sudo tee -a /etc/hosts
```

Эквивалент: [`wsl-local-dns`](./Makefile#L53).

Проверка:

```sh
getent hosts gitlab.local registry.local labs.local
curl -I http://gitlab.local:8929/users/sign_in
curl -I http://registry.local:5050/v2/
```

Ответ Registry `401 Unauthorized` является успешным: сервер доступен и требует
авторизацию.

## 10. Подключение Локального Registry К k3s

K3s использует `containerd`, а локальный Registry работает по HTTP. Нужно
явно разрешить endpoint:

```sh
sudo mkdir -p /etc/rancher/k3s
sudo cp registries.yaml /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
```

Эквивалент: [`k3s-registry-config`](./Makefile#L61).

Проверка:

```sh
sudo cat /etc/rancher/k3s/registries.yaml
systemctl is-active k3s
k3s-kubectl get nodes
```

## 11. DNS Внутри Kubernetes

Pod не использует `/etc/hosts` WSL. Имена нужно добавить в CoreDNS:

```sh
WINDOWS_HOST_IP="$(ip route show default | awk 'NR == 1 {print $3}')"
NODE_IP="$(k3s-kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
```

Получить текущий `NodeHosts`:

```sh
k3s-kubectl -n kube-system get configmap coredns \
  -o jsonpath='{.data.NodeHosts}'
```

Практически обновление выполняет инфраструктурный скрипт:

```sh
KUBECONFIG="$HOME/.kube/k3s.yaml" \
  sh configure-coredns-local-hosts.sh "$WINDOWS_HOST_IP"
```

Эквивалент: [`k3s-local-dns`](./Makefile#L67).

Результат:

```text
gitlab.local   -> Windows/Docker Desktop
registry.local -> Windows/Docker Desktop
labs.local     -> k3s node
```

Проверка из Pod:

```sh
k3s-kubectl run dns-check \
  --rm -it \
  --restart=Never \
  --image=busybox:1.36 \
  -- nslookup gitlab.local
```

## 12. Создание GitLab-Проекта

В GitLab создать:

```text
Group:   simodo-labs
Project: driving-school
```

Проект лучше создать пустым, без README.

Ожидаемый Registry path:

```text
registry.local:5050/simodo-labs/driving-school
```

## 13. Установка GitLab Runner

В GitLab:

```text
Project
-> Settings
-> CI/CD
-> Runners
-> New project runner
```

Рекомендуемые параметры:

```text
Description: local-k3s-runner
Run untagged jobs: enabled
```

Скопировать runner authentication token.

Установить Runner:

```sh
k3s-kubectl create namespace gitlab-runner \
  --dry-run=client -o yaml |
  k3s-kubectl apply -f -

helm repo add gitlab https://charts.gitlab.io
helm repo update

helm upgrade --install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --set gitlabUrl=http://gitlab.local:8929 \
  --set runnerToken='<RUNNER_TOKEN>' \
  --values runner-values.yaml

k3s-kubectl -n gitlab-runner rollout status deployment/gitlab-runner \
  --timeout=180s
```

Эквивалент: [`runner-install`](./Makefile#L93).

Проверка:

```sh
k3s-kubectl -n gitlab-runner get pods
k3s-kubectl -n gitlab-runner logs deployment/gitlab-runner --tail=100
```

Runner должен отображаться в GitLab как `online`.

В этом стенде используется Kubernetes Executor:

```text
Runner Deployment постоянно работает в namespace gitlab-runner.
На каждую job создается отдельный временный Pod.
После завершения job Pod удаляется.
```

## 14. Создание Namespace Работы

Название namespace совпадает с названием работы:

```text
driving-school
delivery
marketplace
```

Студент в имени namespace и URL не используется.

Сгенерировать общие манифесты:

```sh
WORK_NAME=driving-school \
KUBE_NAMESPACE=driving-school \
K8S_OUT=.generated/driving-school \
RUNNER_NAMESPACE=gitlab-runner \
sh render-work.sh
```

Применить:

```sh
k3s-kubectl apply -f .generated/driving-school/00-namespace.yaml
k3s-kubectl apply -f .generated/driving-school/01-runner-deploy-rbac.yaml
```

Эквивалент: [`work-namespace`](./Makefile#L79).

Проверка:

```sh
k3s-kubectl get namespace driving-school
k3s-kubectl -n driving-school get quota,limitrange,role,rolebinding
```

Проверить право deploy job на Traefik Middleware:

```sh
k3s-kubectl auth can-i get middlewares.traefik.io \
  --namespace driving-school \
  --as=system:serviceaccount:gitlab-runner:default
```

Ожидается `yes`.

## 15. Доступ k3s К Приватному Registry

В GitLab:

```text
Project
-> Settings
-> Repository
-> Deploy tokens
```

Создать:

```text
Name:  k3s-image-pull
Scope: read_registry
```

Создать Kubernetes Secret:

```sh
k3s-kubectl -n driving-school create secret docker-registry gitlab-registry \
  --docker-server=registry.local:5050 \
  --docker-username='<DEPLOY_TOKEN_USER>' \
  --docker-password='<DEPLOY_TOKEN>' \
  --dry-run=client -o yaml |
  k3s-kubectl apply -f -
```

Эквивалент: [`registry-secret`](./Makefile#L84).

Проверить только наличие, не выводя содержимое:

```sh
k3s-kubectl -n driving-school get secret gitlab-registry
```

Deploy token нельзя записывать в README, shell history или коммитить в Git.

## 16. Подключение Репозитория Driving School

В репозитории:

```sh
cd /mnt/c/Users/artrsyf/Desktop/uni/strpo/drivingschool

git remote add local-gitlab \
  http://gitlab.local:8929/simodo-labs/driving-school.git

git push -u local-gitlab HEAD
```

Для HTTP-аутентификации использовать Personal Access Token, а не пароль.

В GitLab указать CI configuration file:

```text
Project
-> Settings
-> CI/CD
-> General pipelines
-> CI/CD configuration file

deploy/local-k3s/gitlab-ci.yml
```

## 17. Как Работает Pipeline

### Build

GitLab Runner создает временный Pod с Kaniko:

```text
Kaniko читает Dockerfile
-> скачивает altlinux/base:p10
-> выполняет RUN/COPY
-> формирует OCI layers
-> push в registry.local:5050
```

Push образа выполняет сам Kaniko:

```sh
/kaniko/executor \
  --context "$CI_PROJECT_DIR" \
  --dockerfile "$CI_PROJECT_DIR/deploy/local-k3s/Dockerfile" \
  --destination "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA" \
  --destination "$CI_REGISTRY_IMAGE:latest" \
  --insecure-registry "$CI_REGISTRY"
```

Docker daemon, Docker socket и DinD не используются.

### Deploy

Отдельный Pod с `kubectl` выполняет:

```sh
kubectl apply -f deploy/local-k3s/app.yaml
kubectl -n driving-school set image \
  deployment/driving-school \
  driving-school="$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA"
kubectl -n driving-school rollout status \
  deployment/driving-school \
  --timeout=180s
```

ServiceAccount CI имеет права только через RoleBinding namespace работы.

### Smoke

Отдельный Pod с curl обращается к Traefik внутри кластера:

```sh
curl -fsS \
  -H 'Host: labs.local' \
  http://traefik.kube-system.svc.cluster.local/driving-school/students
```

`Host` нужен для выбора Ingress-правила. Traefik снимает prefix
`/driving-school`, после чего SIMODO получает путь `/students`.

## 18. Проверка Развертывания

```sh
k3s-kubectl -n driving-school get deployment,pods,services,ingress
k3s-kubectl -n driving-school get endpoints
k3s-kubectl -n driving-school logs deployment/driving-school --tail=200
k3s-kubectl -n driving-school exec deployment/driving-school -- ss -ltnp
```

Ожидаемые порты внутри Pod:

```text
2022 stellar-base
8081 students station
8082 training station
8083 exams station
```

Проверка из WSL:

```sh
curl -i http://labs.local/driving-school/students
curl -i http://labs.local/driving-school/training-plans
curl -i http://labs.local/driving-school/exam-applications
```

## 19. Особенности SIMODO, Выявленные При Развертывании

### Пустые агрегаты

Текущий runtime нестабильно обрабатывает чтение отсутствующего агрегата.
Стартовый скрипт создает агрегаты до запуска station.

### Процессы station

Один Pod `driving-school` запускает:

```text
один stellar-base
три stellar-station
```

Startup script контролирует дочерние процессы и завершает контейнер, если один
из station неожиданно остановился. Kubernetes после этого перезапускает Pod.

### Пользователь контейнера

Запуск только с числовым `USER 10001`, отсутствующим в `/etc/passwd`, приводил
к завершению station при первом запросе. Образ создает зарегистрированного
пользователя `simodo` с UID `10001` и домашней директорией `/home/simodo`.

### Диагностика

SIMODO пишет логи в `/tmp`. Startup script передает их в stdout через `tail`,
поэтому они доступны:

```sh
k3s-kubectl -n driving-school logs deployment/driving-school
```

## 20. Ограниченный Контекст Студента

Создать ServiceAccount, RoleBinding и временный kubeconfig:

```sh
WORK_NAME=driving-school \
KUBE_NAMESPACE=driving-school \
STUDENT_NAME=ivan \
TOKEN_DURATION=8h \
KUBECONFIG="$HOME/.kube/k3s.yaml" \
sh create-student-context.sh
```

Эквивалент: [`student-context`](./Makefile#L108).

Результат:

```text
.generated/access/driving-school-ivan.kubeconfig
```

Использование:

```sh
KUBECONFIG=.generated/access/driving-school-ivan.kubeconfig \
  kubectl get pods

KUBECONFIG=.generated/access/driving-school-ivan.kubeconfig \
  kubectl logs deployment/driving-school

KUBECONFIG=.generated/access/driving-school-ivan.kubeconfig \
  kubectl rollout restart deployment/driving-school
```

Разрешено:

```text
просматривать Pods, Services, Endpoints и Events
читать логи
просматривать Deployment, ReplicaSet и Ingress
перезапускать Deployment
```

Запрещено:

```text
читать Secrets
использовать pods/exec
создавать и удалять workloads
изменять RBAC и квоты
работать в других namespaces
```

Проверка:

```sh
STUDENT_CONFIG=.generated/access/driving-school-ivan.kubeconfig

KUBECONFIG="$STUDENT_CONFIG" kubectl auth can-i get pods
KUBECONFIG="$STUDENT_CONFIG" kubectl auth can-i get secrets
KUBECONFIG="$STUDENT_CONFIG" kubectl auth can-i create deployments
```

Ожидается:

```text
yes
no
no
```

Для удаленного студента нужно передать доступный Kubernetes API:

```sh
WORK_NAME=driving-school \
KUBE_NAMESPACE=driving-school \
STUDENT_NAME=ivan \
TOKEN_DURATION=8h \
API_SERVER=https://k3s.example.edu:6443 \
KUBECONFIG="$HOME/.kube/k3s.yaml" \
sh create-student-context.sh
```

Адрес должен быть доступен по сети и включен в TLS SAN сертификата k3s.

## 21. Добавление Новой Работы

Для `delivery`:

```sh
WORK_NAME=delivery \
KUBE_NAMESPACE=delivery \
K8S_OUT=.generated/delivery \
RUNNER_NAMESPACE=gitlab-runner \
sh render-work.sh

k3s-kubectl apply -f .generated/delivery/00-namespace.yaml
k3s-kubectl apply -f .generated/delivery/01-runner-deploy-rbac.yaml
```

Создать deploy token проекта и Secret:

```sh
k3s-kubectl -n delivery create secret docker-registry gitlab-registry \
  --docker-server=registry.local:5050 \
  --docker-username='<DEPLOY_TOKEN_USER>' \
  --docker-password='<DEPLOY_TOKEN>'
```

В репозитории `delivery` нужны аналоги:

```text
deploy/local-k3s/Dockerfile
deploy/local-k3s/run-simodo.sh
deploy/local-k3s/app.yaml
deploy/local-k3s/gitlab-ci.yml
```

## 22. Безопасная Остановка

В WSL:

```sh
sudo systemctl stop k3s
systemctl is-active k3s
```

В PowerShell:

```powershell
cd C:\Users\artrsyf\Desktop\uni\strpo\simodo-labs-infra\local-k3s
docker compose stop
docker compose ps
wsl --shutdown
```

Не выполнять:

```text
docker compose down -v
/usr/local/bin/k3s-uninstall.sh
```

Они удаляют данные.

## 23. Повторный Запуск

1. Запустить Docker Desktop.
2. В PowerShell поднять GitLab:

```powershell
cd C:\Users\artrsyf\Desktop\uni\strpo\simodo-labs-infra\local-k3s
docker compose up -d
```

3. Открыть WSL и запустить k3s:

```sh
sudo systemctl start k3s
k3s-kubectl get nodes
```

4. После изменения WSL/Windows IP повторить DNS-настройки:

```sh
sh configure-wsl-local-hosts.sh
KUBECONFIG="$HOME/.kube/k3s.yaml" sh configure-coredns-local-hosts.sh
```

5. Проверить:

```sh
curl -I http://gitlab.local:8929/users/sign_in
curl -I http://registry.local:5050/v2/
curl -i http://labs.local/driving-school/students
k3s-kubectl -n gitlab-runner get pods
k3s-kubectl -n driving-school get pods
```

## 24. Отличия От Серверного Развертывания

На сервере сохраняется та же архитектура, но заменяются:

```text
локальные DNS -> реальные DNS
HTTP -> TLS
WSL -> Linux VM
Docker Desktop -> отдельная GitLab VM или Linux Docker host
127.0.0.1 -> публичный/private network address
локальный k3s API -> защищенный API с firewall
локальные volumes -> backup и persistent storage
```

Перед эксплуатацией нужны:

```text
TLS для GitLab, Registry и Ingress
firewall для Kubernetes API
backup GitLab и Registry
NetworkPolicy
ResourceQuota для gitlab-runner
раздельные ServiceAccount для build/deploy
централизованные логи и мониторинг
регламент ротации deploy token и student token
```


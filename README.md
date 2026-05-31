# Автошкола на SIMODO/s-script

Это MVP микросервисного проекта для домена автошколы. Проект написан на
`s-script` и запускается через компоненты SIMODO/loom:

- `simodo-stellar-station` - HTTP-фасад, который принимает REST-запросы;
- `simodo-stellar-base` - локальное SIMODO-хранилище агрегатов;
- `s-script` файлы в `src/` - прикладная логика сервисов.

Публичные контракты лежат в `oas/`, пользовательские сценарии и карта
контекстов - в `doc/`.

## Сервисы

В текущем MVP поднимаются три HTTP-сервиса:

- Student Service: `http://localhost:8081`
- Training Service: `http://localhost:8082`
- Exam Service: `http://localhost:8083`

Каждый сервис обслуживается отдельным процессом `simodo-stellar-station`, но все
они используют один локальный процесс `simodo-stellar-base` на порту `2022`.

## Как устроен SIMODO runtime

`simodo-stellar-station` работает как HTTP-обертка над директориями и файлами
`s-script`.

Первый сегмент URL выбирает входной файл:

- `GET /students` вызывает `src/students.s-script`;
- `POST /training-plans/...` вызывает `src/training-plans.s-script`;
- `PATCH /lessons/...` вызывает `src/lessons.s-script`;
- `GET /exam-applications/...` вызывает `src/exam-applications.s-script`.

Входной файл разбирает метод, путь, query-параметры и тело запроса, а затем
делегирует работу в файлы внутри директории сущности:

- `src/students/add.s-script`
- `src/students/get.s-script`
- `src/students/patch.s-script`
- `src/training-plans/add.s-script`
- `src/training-plans/get.s-script`
- `src/training-plans/patch.s-script`
- `src/exam-applications/add.s-script`
- `src/exam-applications/get.s-script`
- `src/exam-applications/patch.s-script`

Подключение к хранилищу задается в специальных файлах:

- `src/students/-base-setup.s-script`
- `src/training-plans/-base-setup.s-script`
- `src/exam-applications/-base-setup.s-script`

В них указаны:

- `server` - хост `simodo-stellar-base`;
- `port` - порт `simodo-stellar-base`;
- `database` - имя базы;
- `aggregate` - имя агрегата внутри базы.

Сейчас все сервисы настроены на локальное хранилище внутри контейнера:

```s-script
const string :
    server = "localhost",
    database = "drivingschool-students",
    aggregate = "students"

const int :
    port = 2022
```

Важно: `localhost` здесь означает не Windows-хост и не WSL-хост, а сетевое
пространство контейнера, внутри которого запущены `station` и `base`.

## Хранилище SIMODO/base

`simodo-stellar-base` не является PostgreSQL, SQLite, MongoDB или другой
классической СУБД. Это SIMODO-хранилище агрегатов, которое держит состояние в
памяти и пишет его в файлы.

Для каждой базы создаются файлы вида:

```text
<base_dir>/<database>
<base_dir>/<database>.events
<base_dir>/<database>.backup
```

В этом проекте используются такие базы и агрегаты:

- `drivingschool-students`, агрегат `students`;
- `drivingschool-training`, агрегат `plans`;
- `drivingschool-exams`, агрегат `applications`.

Текущая модель хранения простая: сервис читает агрегат, меняет запись и пишет
агрегат обратно. Поэтому есть важное ограничение: нельзя безопасно выполнять
параллельные изменения одного и того же агрегата.

Практический вывод:

- не запускайте параллельно несколько `POST`/`PATCH` к одному и тому же
  студенту, учебному плану или заявке;
- особенно осторожно с Training Service, потому что занятия embedded-вложены в
  запись учебного плана;
- демонстрационные и CI-сценарии специально выполняются последовательно.

Это ограничение важно учитывать при развитии проекта. Для настоящей
многопользовательской нагрузки понадобится либо дисциплина последовательных
команд, либо отдельный механизм блокировок/версий, либо другое хранилище.

## Подготовка окружения

Рекомендуемый путь разработки - Linux или WSL. SIMODO сейчас нормально
поддерживается именно в Linux-окружении.

Нужно иметь:

- Docker Engine;
- WSL/Linux shell;
- `curl`;
- доступ к сборке Docker-образа.

Из Windows PowerShell лучше не отправлять inline JSON напрямую. Для запросов
используйте WSL/Linux `curl` и payload-файлы через `--data-binary @file`.

Если запускаете из WSL:

```bash
cd /mnt/c/Users/artrsyf/Desktop/uni/strpo/drivingschool
```

Если запускаете из Linux:

```bash
cd /path/to/drivingschool
```

## Локальный запуск

Собрать образ:

```bash
docker build -t drivingschool-simodo .
```

Поднять контейнер с локальным `simodo-stellar-base` и тремя HTTP-сервисами:

```bash
sh test/00-run-local
```

Скрипт делает следующее:

1. Собирает Docker-образ `drivingschool-simodo`.
2. Удаляет старый контейнер `drivingschool-simodo-local`, если он есть.
3. Создает SIMODO runtime-директории в `/tmp/simodo`.
4. Копирует стандартные файлы `base-setup.json`, `station-setup.json` и
   `initial-contracts.s-script`.
5. Запускает `simodo-stellar-base 2022 /tmp/simodo/db`.
6. Запускает три процесса `simodo-stellar-station`:
   - порт `8081` для Student Service;
   - порт `8082` для Training Service;
   - порт `8083` для Exam Service.

Проверить, что контейнер жив:

```bash
docker ps
docker logs drivingschool-simodo-local
```

Посмотреть логи SIMODO внутри контейнера:

```bash
docker exec drivingschool-simodo-local sh -lc 'cat /tmp/base.log /tmp/students.log /tmp/training.log /tmp/exams.log'
```

Остановить контейнер:

```bash
docker rm -f drivingschool-simodo-local
```

## Запуск с удаленным simodo-stellar-base

Рабочий и рекомендуемый режим для этого MVP - локальный `simodo-stellar-base`
внутри контейнера. Он воспроизводим и не зависит от внешней машины.

Удаленный `simodo-stellar-base` возможен, но тогда нужно явно поменять хост в
файлах `-base-setup.s-script`. Например, для хоста `185.221.215.236`:

```s-script
const string :
    server = "185.221.215.236",
    database = "drivingschool-students",
    aggregate = "students"

const int :
    port = 2022
```

Такое изменение нужно сделать для всех сервисов:

- `src/students/-base-setup.s-script`;
- `src/training-plans/-base-setup.s-script`;
- `src/exam-applications/-base-setup.s-script`.

После этого можно запускать только `station`-процессы, а `base` должен быть уже
доступен на удаленной машине. Если оставить `server = "localhost"`, сервисы в
контейнере будут искать `base` внутри этого же контейнера, а не на вашей
машине.

Для удаленного режима также нужно убедиться, что:

- порт `2022` открыт и доступен из контейнера;
- версии SIMODO на `station` и `base` совместимы;
- базы и агрегаты на удаленной стороне не используются параллельно другими
  сценариями.

## Проверка s-script синтаксиса

Можно отдельно прогнать парсер по всем `s-script` файлам:

```bash
docker run --rm -v "$PWD":/workspace drivingschool-simodo sh -lc '
  find /workspace/src -name "*.s-script" -print | while read f; do
    simodo-parse -G /usr/share/simodo/grammar "$f" >/tmp/parse.out 2>&1 || {
      echo "PARSE_FAIL:$f"
      cat /tmp/parse.out
      exit 1
    }
  done
  echo OK
'
```

## Curl/Postman-like сценарии

Все демонстрационные запросы лежат в `test/`. Они играют роль простой
Postman-коллекции, но в виде переносимых shell/curl сценариев.

Запустить полный бизнес-сценарий:

```bash
sh test/99-demo-flow
```

Запустить сценарии по частям:

```bash
sh test/01-student-flow
sh test/02-training-flow
sh test/03-exam-flow
```

Проверить не только ответы глазами, но и автоматическими smoke-assertions:

```bash
sh test/98-smoke-check
```

`test/98-smoke-check` сохраняет вывод полного сценария в
`/tmp/drivingschool-demo.out` и проверяет:

- наличие успешного создания сущностей через `HTTP/1.1 201 Created`;
- наличие ожидаемой доменной ошибки через `HTTP/1.1 400 Bad Request`;
- созданные публичные id:
  - `student-0`;
  - `training-plan-0`;
  - `training-plan-0-lesson-0`;
  - `exam-application-0`;
- финальный статус студента `ExamPassed`;
- финальный статус учебного плана/заявки `Completed`;
- результат экзамена `Passed`;
- текст ошибки при попытке завершить учебный план до завершения занятий.

## Бизнес-сценарии

Сценарий `01-student-flow` покрывает регистрацию и изменение состояния ученика:

1. Создать ученика.
2. Получить список учеников.
3. Получить ученика по id.
4. Перевести ученика в статус `InTraining`.

Сценарий `02-training-flow` покрывает учебный процесс:

1. Создать учебный план для ученика.
2. Добавить занятие.
3. Попробовать завершить учебный план до завершения занятий.
4. Получить ожидаемый `400 Bad Request`.
5. Завершить занятие.
6. Завершить учебный план.
7. Перевести ученика в статус `TrainingCompleted`.

Сценарий `03-exam-flow` покрывает экзаменационный процесс:

1. Создать заявку на экзамен.
2. Получить заявку по id.
3. Отправить заявку в ГАИ.
4. Записать результат `Passed`.
5. Перевести ученика в статус `ExamPassed`.

Файл `99-demo-flow` объединяет эти сценарии в один сквозной процесс:

```text
регистрация ученика -> обучение -> завершение обучения -> экзамен -> успешная сдача
```

## Payload-файлы

Тела запросов лежат в `test/payloads/`. Пример отправки:

```bash
curl -i \
  -H "Content-Type: application/json" \
  --data-binary "@test/payloads/student-create.json" \
  http://localhost:8081/students
```

Использование `--data-binary @file` важно: так тело запроса уходит в SIMODO без
искажений оболочкой.

## Проблемы, которые встретились при запуске

### Экранирование кавычек

PowerShell и shell по-разному обрабатывают кавычки. Inline JSON вроде:

```powershell
curl -d '{"fullName":"..."}'
```

может прийти в сервис не тем телом, которое ожидается. В результате SIMODO
получает пустое, поврежденное или неправильно экранированное тело.

Решение: хранить JSON в файлах и отправлять через Linux/WSL `curl`:

```bash
curl --data-binary "@test/payloads/student-create.json"
```

### interpret error

`interpret error` в SIMODO часто означает не бизнес-ошибку, а проблему на уровне
интерпретации `s-script`:

- синтаксическая ошибка в `.s-script`;
- попытка работать с полем не того типа;
- повторный разбор уже разобранного тела запроса;
- некорректная структура данных после невалидного JSON.

Важный нюанс `simodo-stellar-station`: тело запроса уже попадает в `s.body` как
структура, если клиент прислал валидный JSON. Поэтому его не нужно повторно
парсить как строку.

### JSON vs JSON5

Для HTTP request body используйте строгий JSON:

- двойные кавычки;
- без комментариев;
- без trailing comma;
- без одинарных кавычек;
- `Content-Type: application/json`.

JSON5-стиль удобен для человека, но в этих запросах приводит к ошибкам разбора.

Отдельно: конфигурационные файлы SIMODO имеют имена вроде `base-setup.json` и
`station-setup.json`, но для клиентских HTTP-запросов ориентируемся именно на
строгий JSON.

### Runtime-директории SIMODO

`simodo-stellar-base` ожидает, что нужные директории уже существуют. Если не
создать `/tmp/simodo/db` и соседние runtime-пути, можно получить низкоуровневые
ошибки вида:

```text
basic_ios::clear: iostream error
```

Поэтому `test/00-run-local` перед стартом создает:

```text
/tmp/simodo/bin
/tmp/simodo/data/stellar
/tmp/simodo/data/contracts
/tmp/simodo/tmp/logs/work
/tmp/simodo/tmp/logs
/tmp/simodo/db
```

## GitLab CI

CI описан в `.gitlab-ci.yml`.

Пайплайн не использует Docker-in-Docker. Это важно: на текущем GitLab runner
`docker:dind` не стартует без privileged-доступа, из-за чего Docker daemon
недоступен на `docker:2375`.

Вместо этого CI использует образ `alt:p10`, подключает RPM-репозиторий SIMODO,
ставит `simodo-loom`, `simodo-loom-stellar` и `curl`, а затем запускает
`simodo-stellar-base` и три `simodo-stellar-station` прямо внутри job container.

Команды проверки:

```bash
sh test/00-run-ci
sh test/98-smoke-check
```

После выполнения сохраняются artifacts:

- `demo.out` - полный вывод demo-flow;
- `simodo.log` - логи `base`, `students`, `training`, `exams`;
- `index.html` - копия логов для быстрой публикации/просмотра.

Также есть job `pages`, который публикует `demo.out` как простую HTML-страницу
на ветках `main` и `master`.

Локальный Docker-запуск при этом остается в `test/00-run-local`; CI-запуск
вынесен отдельно в `test/00-run-ci`, чтобы не зависеть от Docker daemon внутри
GitLab runner.

## Модель id

В OpenAPI публичные идентификаторы описаны как UUID strings. Внутри
`simodo-stellar-base` для записей используются числовые id. В этом MVP наружу
отдаются стабильные строковые id:

- `student-0`;
- `training-plan-0`;
- `training-plan-0-lesson-0`;
- `exam-application-0`.

Числовой id SIMODO остается внутренним ключом хранения.

## Быстрый чек-лист

```bash
cd /mnt/c/Users/artrsyf/Desktop/uni/strpo/drivingschool
docker build -t drivingschool-simodo .
sh test/00-run-local
sh test/98-smoke-check
sh test/99-demo-flow
docker rm -f drivingschool-simodo-local
```

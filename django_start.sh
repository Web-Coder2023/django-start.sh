#!/bin/bash

# === Ввод переменных с умолчаниями ===

read -p "Введите полный путь к проекту [$(pwd)]: " FULL_PATH
FULL_PATH=${FULL_PATH:-$(pwd)}
FULL_PATH=$(realpath "$FULL_PATH")

read -p "Введите имя папки проекта: " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
  echo "❌ Имя папки проекта обязательно"
  exit 1
fi

read -p "Введите имя конфигурации Django (например, config) [config]: " CONFIG_NAME
CONFIG_NAME=${CONFIG_NAME:-config}

read -p "Введите имя БД: " DB_NAME
read -p "Введите имя пользователя БД: " DB_USER
read -sp "Введите пароль пользователя БД: " DB_PASSWORD
echo
read -p "Введите ALLOWED_HOSTS (через пробел, без кавычек): " ALLOWED_HOSTS
read -p "Введите email для суперпользователя: " ADMIN_EMAIL
read -p "Введите имя суперпользователя: " ADMIN_USERNAME
read -sp "Введите пароль суперпользователя: " ADMIN_PASSWORD
echo

PROJECT_PATH="$FULL_PATH/$PROJECT_NAME"
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH" || { echo "Не удалось перейти в $PROJECT_PATH"; exit 1; }

echo "📁 Рабочая директория: $(pwd)"

python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install django psycopg2-binary djangorestframework python-dotenv drf-yasg Pillow gunicorn

cat > requirements.txt <<EOF
django
psycopg2-binary
djangorestframework
python-dotenv
drf-yasg
Pillow
gunicorn
EOF

echo "Создаём Django-проект с конфигом: $CONFIG_NAME"
django-admin startproject "$CONFIG_NAME" .

SETTINGS_FILE="$PROJECT_PATH/$CONFIG_NAME/settings.py"
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "❌ Файл настроек не найден: $SETTINGS_FILE"
  exit 1
fi
echo "✅ Файл настроек найден: $SETTINGS_FILE"

echo "Создаём пользователя PostgreSQL, если он не существует..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER'
   ) THEN
      CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
   END IF;
END
\$do\$;
EOF

echo "Проверяем, существует ли база данных '$DB_NAME'..."
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
if [ "$DB_EXISTS" != "1" ]; then
  echo "Создаём базу данных '$DB_NAME' с владельцем '$DB_USER'..."
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
else
  echo "База данных '$DB_NAME' уже существует, пропускаем создание"
fi

cat > .env <<EOF
SECRET_KEY=$(openssl rand -base64 32)
DEBUG=True
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=localhost
DB_PORT=5432
ALLOWED_HOSTS=$ALLOWED_HOSTS
EOF
echo "✅ .env файл создан"

cat > "$SETTINGS_FILE" <<EOF
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv('SECRET_KEY')
DEBUG = os.getenv('DEBUG') == 'True'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS').split()

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'drf_yasg',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = '$CONFIG_NAME.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = '$CONFIG_NAME.wsgi.application'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME'),
        'USER': os.getenv('DB_USER'),
        'PASSWORD': os.getenv('DB_PASSWORD'),
        'HOST': os.getenv('DB_HOST'),
        'PORT': os.getenv('DB_PORT'),
    }
}

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
EOF

echo "✅ settings.py переписан с использованием PostgreSQL и .env"

echo "Применяем миграции..."
python manage.py migrate || { echo "❌ Ошибка миграций"; exit 1; }
echo "✅ Миграции применены"

echo "Создаём суперпользователя..."
echo "from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='$ADMIN_USERNAME').exists():
    User.objects.create_superuser('$ADMIN_USERNAME', '$ADMIN_EMAIL', '$ADMIN_PASSWORD')
" | python manage.py shell || { echo "❌ Ошибка создания суперпользователя"; exit 1; }
echo "✅ Суперпользователь создан"

# === Git инициализация ===
read -p "Введите ссылку на удалённый Git-репозиторий (или оставьте пустым, чтобы пропустить): " GIT_REPO_URL

cd "$PROJECT_PATH" || { echo "Не удалось перейти в $PROJECT_PATH"; exit 1; }

# Создаём .gitignore
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
*.so
*.egg
*.egg-info/
dist/
build/

# Django
*.log
local_settings.py
db.sqlite3
media/
staticfiles/

# Env
.env
venv/
ENV/
env/
.venv/

# IDE
.idea/
.vscode/
*.swp
EOF
echo "✅ Файл .gitignore создан"

# Инициализация Git
if [ ! -d ".git" ]; then
  git init -b main
  echo "✅ Git репозиторий инициализирован (ветка main)"
fi

git add .
git commit -m "Initial Django project setup"
echo "✅ Первый коммит создан"

if [ -n "$GIT_REPO_URL" ]; then
  git remote add origin "$GIT_REPO_URL"
  echo "✅ Удалённый репозиторий подключён: $GIT_REPO_URL"
fi

echo ""
echo "🎉 Django-проект успешно создан и настроен!"
echo "📂 Путь: $PROJECT_PATH"
echo "🐘 PostgreSQL: БД '$DB_NAME', пользователь '$DB_USER'"
echo "⚙️ Конфиг Django: $CONFIG_NAME/settings.py"
echo "📝 .env заполнен"
echo "🚀 Миграции применены и суперпользователь '$ADMIN_USERNAME' создан"
echo "👉 Запускайте проект командой: python manage.py runserver"

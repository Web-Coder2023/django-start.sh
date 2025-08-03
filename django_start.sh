django_start() {
    # Получаем имя текущего пользователя
    CURRENT_USER=$(whoami)

    # Путь по умолчанию: /home/<текущий_пользователь>/files
    read -p "Где создать проект? (абсолютный путь, Enter для /home/$CURRENT_USER/files): " PROJECT_PATH
    PROJECT_PATH=${PROJECT_PATH:-/home/$CURRENT_USER/files}

    # Имя папки проекта
    read -p "Имя папки проекта: " PROJECT_NAME
    if [[ -z "$PROJECT_NAME" ]]; then
        echo "❌ Имя проекта не может быть пустым."
        return 1
    fi

    # Имя конфига проекта
    read -p "Имя конфига проекта (по умолчанию: config): " CONFIG_NAME
    CONFIG_NAME=${CONFIG_NAME:-config}

    # Переход в указанный каталог
    mkdir -p "$PROJECT_PATH/$PROJECT_NAME"
    cd "$PROJECT_PATH/$PROJECT_NAME" || { echo "❌ Ошибка перехода в каталог."; return 1; }

    echo "📁 Создание виртуального окружения..."
    python3 -m venv venv
    source venv/bin/activate

    echo "⬇️ Установка Django и psycopg2-binary..."
    pip install --upgrade pip
    pip install django psycopg2-binary

    echo "⚙️ Инициализация Django-проекта..."
    django-admin startproject "$CONFIG_NAME" .

    echo "📝 Создание requirements.txt и .env..."
    pip freeze > requirements.txt
    echo -e "DEBUG=True\nSECRET_KEY=your-secret-key\nDB_NAME=your-db-name\nDB_USER=your-db-user\nDB_PASSWORD=your-db-password" > .env

    echo "✅ Django-проект успешно создан!"
    echo "📂 Путь: $PROJECT_PATH/$PROJECT_NAME"
    echo "⚙️ Конфиг: $CONFIG_NAME"
    echo "🐍 Виртуальное окружение: venv (в корне проекта)"
    echo "📦 Установлены: django, psycopg2-binary"
    echo "📝 Созданы: requirements.txt, .env"
    echo ""
    echo "🚀 Ты уже в папке проекта с активированным окружением"
}

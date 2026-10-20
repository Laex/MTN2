# Сторонние компоненты

## 7-Zip (`plugins\mtn.7z\7z.dll`)

В комплект входит библиотека `7z.dll` программы [7-Zip](https://www.7-zip.org) (x64), Copyright (C) 1999–2025 Igor Pavlov.
Плагин `mtn.7z` использует её, чтобы открывать архивы 7z и другие форматы. Исходный код 7-Zip доступен на
[www.7-zip.org](https://www.7-zip.org).

Лицензия `7z.dll`: GNU LGPL (версии 2.1 и выше) для большей части кода; GNU LGPL с ограничением unRAR для части кода;
BSD 3-clause (декомпрессия LZFSE и ZSTD) и BSD 2-clause (XXH64) для остального. Полные тексты и сведения об авторских
правах – в файле `plugins\mtn.7z\license.txt`.

Ограничение unRAR: код распаковки RAR создан на основе исходников unRAR, права на которые принадлежат Alexander Roshal;
этот код нельзя использовать для создания RAR-совместимого (WinRAR) архиватора.

Библиотека подключается динамически и лежит отдельным файлом: её можно заменить своей сборкой 7-Zip, положив
x64-версию `7z.dll` в `plugins\mtn.7z\`. Автообновление заменяет `7z.dll` версией из нового пакета.

## libcurl (`plugins\mtn.net\libcurl-x64.dll`)

Плагин `mtn.net` говорит с серверами через библиотеку [curl](https://curl.se) (libcurl), Copyright (C) Daniel Stenberg и участники проекта. Лицензия curl – MIT-подобная, её текст лежит в `plugins\mtn.net\COPYING.txt`.

В поставляемую сборку (официальная Windows-сборка с curl.se) входят статически собранные библиотеки: LibreSSL (лицензии OpenSSL/SSLeay и ISC), libssh2 (BSD 3-clause), nghttp2, nghttp3 и ngtcp2 (MIT), zlib (zlib), Brotli (MIT), Zstandard (BSD 3-clause) и другие; их лицензии указаны в документации сборки на [curl.se/windows](https://curl.se/windows/).

Библиотека подключается динамически и лежит отдельным файлом: её можно заменить своей сборкой curl с поддержкой FTP, FTPS, SFTP, SCP и HTTPS (`libcurl-x64.dll` в `plugins\mtn.net\`). Загружается библиотека из папки плагина, не из `PATH`.

## Подсветка синтаксиса (`plugins\mtn.highlight`)

Плагин `mtn.highlight` собран из библиотеки [syntect](https://github.com/trishume/syntect) (MIT, Copyright (c) 2017 Tristan Hume, Keith Hall, Google Inc и участники проекта) и описаний синтаксисов из стандартных пакетов Sublime Text ([sublimehq/Packages](https://github.com/sublimehq/Packages)), которые библиотека упаковывает в модуль. Лицензия пакетов разрешает копировать, использовать, изменять, продавать и распространять их без дополнительных условий; синтаксисы YAML (MIT, Copyright (c) 2015 FichteFoll) и Rust (MIT) идут со своими лицензиями, которые требуют сохранять уведомление об авторских правах. Кроме того, в модуль входят библиотеки Rust с лицензиями MIT, Apache-2.0, Unlicense, 0BSD и Zlib (выбрана лицензия MIT или единственная, под которой распространяется библиотека).

Полные тексты лицензий и уведомления об авторских правах – в файле `plugins\mtn.highlight\licenses.md`.


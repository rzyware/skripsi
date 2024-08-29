# Repositori Skripsi
Repositori untuk pengumpulan proyek skripsi.
# Table of Contents
  - [Instalasi pada Smartroom.id](#smartroom)
  - [Instalasi pada Serversec](#serversec)
  - [Akses Scirus & ntopng](#akses-scirius--ntopng)
  - [Bot Whatsapp](#bot-whatsapp)
  - [Dataset](#dataset)
  
## Smartroom
Proses instalasi pada Smartroom dapat dilakukan dengan menjalankan perintah berikut.
  ```sh
  sudo ./installer_smartroom.sh
  ```

Setelah itu, untuk melakukan konfirmasi service berhasil dibuat, dapat menggunakan `systemctl status smartroom-sys.service`. Dan untuk memastikan konfigurasi GRE + tc berhasil, dapat dilakukan dengan menggunakan perintah `ip a` atau `systemctl status gre-tc.service`
## Serversec

Proses instalasi pada Serversec dapat dilakukan dengan menjalankan perintah berikut.
  ```sh
  sudo -E ./installer_serversec.sh
  ```
Setelah itu, terdapat beberapa hal yang perlu diisi:
```sh
Username server:
IP server:
Memori yang dialokasikan untuk Elasticsearch (ex: 2G):
Nomor WhatsApp untuk notifikasi alert (62):
```
Saat menjalankan skrip ini, SSH key akan diperiksa dan dibuat jika belum ada dengan menggunakan `ssh-keygen`. Setelah itu, kunci publik akan disalin ke server remote dengan menggunakan `ssh-copy-id` dan user akan diminta untuk memasukkan sandi akses ke remote host. Proses ini hanya dilakukan sekali dan diperlukan agar proses pengiriman file oleh `rsync` dapat berjalan tanpa perlu memasukkan password.


Setelah proses installer berhasil, service dapat dicek melalui `systemctl status serversec-sys.service`. Untuk memastikan konfigurasi GRE berhasil, dapat dilakukan dengan menggunakan perintah `ip a` atau `systemctl status gre.service`. Autentikasi WhatsApp dapat dilakukan dengan melakukan scan pada QR yang dihasilkan pada file `auth` yang terletak pada `$HOME/serversec/wwebjs/auth`.

## Akses Scirius & ntopng
Setelah melakukan proses instalasi, untuk mengakses Scirius dapat dilakukan dengan memasukkan IP serversec dengan HTTPS di web browser. Untuk mengakses ntopng, dapat dilakukan dengan cara yang sama akan tetapi menggunakan port `3000`.

# Bot Whatsapp
Untuk melihat perintah yang dapat diberikan ke bot alert, dapat mengirimkan perintah `.help` ke bot.

**Catatan:** Bot adalah WhatsApp yang diautentikasi menggunakan QR. Nomor yang dimasukkan saat proses instalasi di Serversec adalah nomer yang memiliki izin untuk mengakses ke perintah yang terdapat pada bot.
## Dataset
Dataset dengan ekstensi csv diproses menggunakan [CICFlowMeter](https://github.com/ahlashkari/CICFlowMeter) sesuai dengan referensi dari dataset [CSE-CIC-IDS2018](https://www.unb.ca/cic/datasets/ids-2018.html). Karena keterbatasan GitHub dalam mengunggah file dengan ukuran besar, dataset CICFlowMeter dan data mentah dari traffic yang di-capture dapat diunduh melalui [Google Drive](https://drive.google.com/drive/folders/1SSXQJJo3ulyAqY5RfIz8yTqrp6kO4hLR?usp=sharing). 

1. Struktur aplikasi sudah dipecah dan dirapikan

Aplikasi yang sebelumnya lebih terpusat sudah dipisahkan menjadi struktur modular:

app
core
features
presentation
domain
data

app.dart sekarang hanya bertugas membangun MaterialApp, memasang tema, dan membuka AppShell.

Komponen umum juga sudah dipindahkan ke lokasi bersama, seperti:

warna dan desain;
page layout;
metric card;
formatter angka;
searchable dropdown;
komponen navigasi.

Duplikasi widget dan logic sudah banyak dikurangi.

2. Navigasi desktop dan mobile sudah disatukan

Sudah dibuat sumber navigasi utama melalui AppDestination.

Destinasi aplikasi meliputi:

Overview
Transactions
Accounts
Categories
Asset Conversion
Projects
Tithe
Reports

Perilakunya:

desktop menggunakan side navigation;
mobile menggunakan bottom navigation;
menu mobile utama: Overview, Transactions, Accounts, dan More;
fitur lain masuk ke bottom sheet More;
tombol Quick Add tersedia melalui FAB.

Navigasi mobile sudah memiliki regression test.

3. Bootstrap aplikasi sudah dipisahkan

Sudah dibuat:

lib/app/services/app_bootstrap_service.dart

Service ini bertanggung jawab untuk:

membuka database;
memastikan seed master data tersedia;
membaca accounts, categories, dan projects;
membaca transaksi;
mengisi controller;
meneruskan error bila bootstrap gagal.

Sudah dibuat juga AppBootstrapErrorView dengan tombol retry.

Bootstrap dan tampilan error-nya sudah diuji.

4. Master data sudah memiliki controller dan persistence yang aman

Accounts, expense categories, income categories, dan projects sekarang dikelola oleh MasterDataController.

Yang sudah diperbaiki:

tambah data;
edit data;
validasi nilai kosong;
pencegahan duplikat;
edit dengan nilai yang tidak berubah tidak menulis ulang database;
state UI baru berubah setelah persistence berhasil;
error persistence tidak membuat UI menampilkan data palsu;
lifecycle TextEditingController pada dialog sudah dibersihkan dengan memakai TextFormField(initialValue:).

Sudah ada test controller dan widget untuk seluruh perilaku tersebut.

5. Rename kategori SQLite sudah diperbaiki

Sebelumnya rename category berpotensi mengganti kategori dengan nama sama pada tipe yang berbeda.

Sekarang rename category:

wajib menerima categoryType;
hanya mengubah kategori pada tipe yang dipilih;
menaikkan version;
mengubah sync_status menjadi pending;
menolak rename category tanpa categoryType.

Contoh kasus yang sudah diuji:

expense category dan income category memiliki nama sama;
rename hanya memengaruhi tipe yang dipilih;
rename berturut-turut menaikkan version;
category type yang hilang ditolak. 6. SQLite FFI sudah dibuat hanya diinisialisasi sekali

LocalStore native sekarang memiliki penjaga statis agar:

sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;

tidak dijalankan berulang kali dalam satu proses test.

Hasilnya:

warning pergantian global database factory sudah hilang;
test SQLite tetap lulus;
analyzer tetap bersih. 7. LocalStore sudah mendukung database path khusus

LocalStore native sekarang menerima:

LocalStore({this.databasePath});

Ini memungkinkan integration test memakai database temporary sendiri tanpa mengganggu database aplikasi.

Versi web juga menerima parameter yang sama untuk menjaga kompatibilitas API, walaupun parameter tersebut tidak digunakan di web.

8. Error transaksi sekarang diteruskan dengan benar

TransactionController.\_run() sebelumnya hanya menyimpan error, tetapi tidak selalu meneruskannya.

Sekarang controller:

menghapus error lama;
menjalankan operasi;
menyimpan pesan error saat gagal;
melakukan rethrow;
tetap memanggil notifier pada akhir operasi.

Dampaknya:

Quick Add mengetahui persistence gagal;
form tidak tertutup ketika save gagal;
detail transaksi tidak tertutup ketika delete gagal;
UI dapat menampilkan pesan error yang nyata. 9. Quick Add, Edit, dan Delete sudah aman terhadap kegagalan
Quick Add

Quick Add sekarang:

menunggu persistence selesai;
mengembalikan false ketika gagal;
tetap terbuka saat database gagal;
tidak menambahkan transaksi palsu ke UI.
Edit Transaction

Form edit sekarang:

memiliki status saving;
tombol dinonaktifkan saat proses;
menampilkan error;
tetap terbuka ketika update gagal;
tidak bisa ditutup sembarangan ketika sedang menyimpan.
Delete Transaction

Dialog detail transaksi sekarang:

stateful;
memiliki status loading;
menampilkan error delete;
tidak langsung tertutup ketika database gagal;
hanya tertutup setelah delete berhasil.

Seluruh alur kegagalan create, edit, dan delete sudah memiliki regression test.

10. Use case transaksi sudah dirapikan

Use case yang tersedia:

CreateTransaction
UpdateTransaction
DeleteTransaction
GetTransactions
DuplicateTransaction

Validasi transaksi mencakup:

deskripsi tidak boleh kosong;
amount tidak boleh negatif;
asset conversion wajib memiliki quantity positif.

Saat create:

version diatur menjadi 1;
updatedAt disamakan dengan createdAt;
syncStatus menjadi pending.

Saat update:

UUID dipertahankan;
version dinaikkan;
updatedAt diperbarui;
syncStatus menjadi pending.

Saat delete:

memakai soft delete;
version dinaikkan;
deletedAt dan updatedAt diisi;
syncStatus menjadi pending. 11. Bug DuplicateTransaction sudah diperbaiki

Sebelumnya transaksi duplikat:

disimpan ke database dengan syncStatus: pending;
tetapi objek yang dikembalikan ke UI masih local_only.

Sekarang objek yang:

disimpan;
dikembalikan;
ditampilkan di UI

adalah objek yang sama dengan syncStatus: pending.

Perilaku ini sudah diuji sampai SQLite.

12. Integration test transaksi SQLite sudah dibuat

Sudah dibuat:

test/local_transaction_repository_test.dart

Test tersebut membuktikan:

transaksi yang dibuat tetap ada setelah database ditutup dan dibuka lagi;
update mempertahankan UUID;
update menaikkan version;
soft delete menghilangkan transaksi dari query aktif;
metadata soft delete tersimpan di tabel;
asset conversion mempertahankan:
quantity;
unit;
unit price;
amount;
transaction type;
transaksi duplikat yang dikembalikan ke UI sama dengan data yang tersimpan.

Konflik nama Transaction antara model aplikasi dan Sqflite juga sudah diselesaikan dengan:

import 'package:sqflite_common_ffi/sqflite_ffi.dart'
hide Transaction; 13. Transaction.copyWith() sekarang bisa menghapus nilai nullable

Sebelumnya copyWith() tidak dapat membedakan antara:

parameter tidak diberikan;
parameter sengaja diberikan null.

Field yang terdampak:

projectId
quantity
unit
unitPrice
deletedAt

Sekarang digunakan sentinel \_unset, sehingga ini bekerja:

transaction.copyWith(
projectId: null,
quantity: null,
unit: null,
unitPrice: null,
deletedAt: null,
);

Sedangkan parameter yang tidak disebut tetap mempertahankan nilai sebelumnya.

Sudah dibuat test untuk:

explicit clearing;
preserving omitted fields. 14. Metadata asset conversion dibersihkan ketika tipe berubah

Saat transaksi Asset Conversion diedit menjadi Expense atau Income, metadata berikut sekarang dihapus:

quantity;
unit;
unit price.

Jadi tidak ada lagi kasus transaksi expense biasa masih membawa metadata emas atau aset lama di database.

15. Filter transaksi sudah memakai bulan aktual

Daftar transaksi sebelumnya masih memiliki tanggal demo July 2026.

Sekarang filter memakai:

awal bulan dari tanggal referensi;
akhir bulan eksklusif;
query pencarian;
kategori;
account;
project;
transaction type.

Query dapat mencari melalui:

title;
category;
account;
project;
type.

Date range juga mencegah rentang tanggal terbalik.

Tombol Reset month sudah tersedia dan memiliki test.

16. Urutan transaksi sudah konsisten

TransactionController sekarang selalu mengurutkan transaksi berdasarkan:

tanggal transaksi terbaru;
createdAt terbaru ketika tanggal transaksi sama.

Sorting dijalankan setelah:

load;
create;
update;
duplicate.

Update transaksi juga menangani kasus objek belum ditemukan di list dengan menambahkannya kembali.

Sudah dibuat test untuk:

load data yang tidak berurutan;
create transaksi backdated;
edit tanggal transaksi;
transaksi pada tanggal sama;
urutan berdasarkan createdAt. 17. Asset Conversion sudah menunggu persistence

AssetConversionScreen dan form-nya sekarang:

memakai callback asynchronous;
memiliki state saving;
menonaktifkan input saat proses;
menampilkan spinner dan teks Saving...;
baru menampilkan sukses setelah database berhasil;
tetap mempertahankan nilai form ketika database gagal.

Sudah ada widget test untuk sukses dan kegagalan persistence.

18. FinancialSummary sudah menjadi pusat kalkulasi keuangan

Sudah dibuat:

lib/features/analytics/domain/financial_summary.dart

Class ini menghitung:

recorded balance;
monthly income;
monthly expenses;
monthly net cash flow;
savings rate;
tithe rate;
monthly tithe;
activity count;
spending by category;
top spending category.

Aturan perhitungan saat ini:

income masuk sebagai pemasukan;
expense masuk sebagai pengeluaran;
transfer tidak memengaruhi cash flow;
asset conversion tidak memengaruhi cash flow;
transaksi soft-deleted diabaikan;
monthly values hanya memakai transaksi dalam bulan referensi;
recorded balance memakai seluruh income dan expense aktif;
kategori pengeluaran diurutkan dari terbesar;
savings rate aman saat income nol.

Sudah diuji dengan lima kelompok kasus utama.

19. Dashboard sudah tidak memakai angka demo

Dashboard sebelumnya berisi angka hardcoded seperti:

Rp 48.620.000
Rp 12.500.000
Rp 6.850.000
Rp 1.925.000

Sekarang Dashboard menerima:

FinancialSummary summary
DateTime referenceDate

Dashboard menampilkan data aktual:

recorded balance;
income bulan berjalan;
expenses bulan berjalan;
calculated tithe;
net cash flow;
spending by category;
transaction activity;
savings rate;
top category;
recent transactions.

Grafik dan goals demo telah diganti dengan ringkasan yang benar-benar berasal dari transaksi.

Tanggal heading juga tidak lagi hardcoded July 18, 2026.

20. Reports sudah memakai data aktual

Reports sekarang menampilkan:

monthly net cash flow;
savings rate;
top spending category;
amount top category;
persentase top category;
jumlah ledger entries.

Angka seperti +Rp 5.650.000, 45.2%, dan Housing 32% sudah tidak ditulis langsung lagi.

21. Tithe page sudah memakai kalkulasi aktual

Tithe page sekarang menampilkan:

calculated monthly tithe;
monthly recorded income;
applied rate;
penjelasan transaksi yang dikecualikan.

Halaman juga menyatakan secara jujur bahwa:

payment tracking belum tersedia;
carry-forward tracking belum tersedia.

Jadi halaman tidak lagi mengklaim saldo tithe pending yang sebenarnya belum memiliki tabel atau data persistence.

22. Widget test halaman finansial sudah dibuat

Sudah dibuat:

test/financial_pages_test.dart

Test membuktikan:

Dashboard menampilkan nilai kalkulasi;
Reports menampilkan net cash flow, savings rate, dan top category;
Tithe menampilkan monthly tithe dan rate;
formatting rupiah tampil sesuai harapan.

Setelah tahap ini total test menjadi:

+67: All tests passed!
Yang belum selesai

1. TithePolicy berbasis tanggal

Tahap berikutnya yang direncanakan adalah mengganti:

titheRate: 0.13

yang masih berada di AppShell.

Rencana arsitekturnya:

lib/features/tithe/domain/tithe_policy.dart

Policy tersebut akan menentukan rate berdasarkan tanggal efektif.

Namun detail tanggal belum boleh dianggap final. Handoff ke Work mode membawa asumsi:

13% mulai 1 Januari 2026;
14% mulai 1 Februari 2026.

Padahal sebelumnya terdapat konteks bahwa 14% dapat dimulai pada waktu tertentu. Jadi tanggal efektif harus dipastikan sebelum implementasi.

2. FinancialSummary masih memiliki default 0.13

Saat ini factory masih memiliki default:

double titheRate = 0.13

Ini belum masalah fungsional, tetapi sebaiknya nanti rate diwajibkan berasal dari TithePolicy.

3. Belum ada persistence untuk aturan tithe

Belum tersedia:

settings table;
tithe rules table;
effective date storage;
paid tithe records;
carry-forward records.

Jadi Tithe sekarang baru kalkulator, belum ledger kewajiban dan pembayaran.

4. Index database fresh install perlu diaudit

Ada potensi schema inconsistency yang belum dikerjakan:

beberapa index dibuat di onUpgrade;
fresh database yang langsung dibuat pada version terbaru mungkin tidak menjalankan bagian upgrade tersebut.

Yang perlu diperiksa:

transaction project index;
account name index;
category index;
project index.

Solusi kemungkinan membutuhkan:

memastikan semua index dibuat dalam onCreate;
migration baru dengan CREATE INDEX IF NOT EXISTS;
test menggunakan PRAGMA index_list. 5. Unique constraint master data belum ada di level database

Controller sudah mencegah duplikat, tetapi database sendiri tampaknya belum memiliki unique constraint penuh.

Artinya jalur lain yang melewati controller masih berpotensi menulis duplikat.

Perbaikan ini lebih besar karena mungkin membutuhkan:

migration database version baru;
partial unique index;
penanganan data duplikat lama;
parity dengan penyimpanan web.
Urutan lanjutan yang paling aman
Pastikan tanggal efektif perubahan tithe.
Buat TithePolicy.
Hapus hardcoded 0.13 dari AppShell.
Buat FinancialSummary menghitung tithe sesuai policy.
Tambahkan test lintas tanggal efektif.
Audit index database untuk fresh install.
Tambahkan database-level uniqueness untuk master data.
Baru lanjut ke persistence settings dan pembayaran tithe.

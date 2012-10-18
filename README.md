p5-MyKintai
===========

Tengで作る勤怠管理システム

## 出来ること

* 出勤と退勤時間の管理
* 不規則な生活からの脱却（出来たらいいな！）

## 実行方法
### 必要なモジュールのインストール

	$ cpanm Teng
	$ cpanm DBD::SQLite
	$ cpanm Mojolicious

### サーバーを起動

	$ chmod 744 mykintai.pl
	$ ./mykintai.pl daemon

## 注意事項

DBのスキーマ定義は検討中
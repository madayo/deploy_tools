#! /bin/bash -xue

SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd $SCRIPT_DIR

eval "$(cat .env <(echo) <(declare -x))"

# 第一引数でどのサーバに対して処理するか指定する
if [ $# -lt 1 ]; then
  echo '[ERROR] please input mode.'
  exit 1
fi
# 第一引数を mode として大文字化
mode=${1^^}
echo "Mode is ${mode}."

# 第二引数が force の場合のみ dry-run モードをスキップ
force_run=${2:-dryrun}
if [ $force_run == "force" ]; then
  echo "force rsync"
else
  echo "dry-run"
fi

# production の場合は一度確認を挟む
if [[ $mode == "PRODUCTION" || $mode == *_PRODUCTION ]]; then
  echo "---------- production !!!!!!!!!!!!!!!!! OK? ----------"
  /bin/echo -n "Y/n: "
  read ans
  if [ $ans != "Y" ]; then
    printf "\e[37;41;1m Stop \e[m\n"
    exit 0
  fi
fi

# mode に合わせて動的に環境変数を読み込む
rsync_remote_ssh_alias="RSYNC_${mode}_REMOTE_SSH_ALIAS"
rsync_remote_dir="RSYNC_${mode}_REMOTE_DIR"

rsync_remote_ssh_alias=$(eval echo '$'$rsync_remote_ssh_alias)
rsync_remote_dir=$(eval echo '$'$rsync_remote_dir)

if [ -z "${rsync_remote_ssh_alias}" ] || [ -z "${rsync_remote_dir}" ]; then
  echo '[ERROR] invalid mode.'
  exit 1
fi

### --size-only はファイルサイズしか見ないので、1文字だけ変更したときなどに変更が検知されないので避けること
# --checksum ハッシュ値の比較。タイムスタンプは意識しない
# --archive パーミッションを維持
# --delete 転送元になくて、転送元にだけあるものを削除
rsync_opt="-v --checksum --archive --delete --exclude-from=rsync_exclude.txt"

# rsync をラップして、処理対象ファイルをわかりやすく表示してから rsync する
function myrsync() {
  local rsync_output=$(rsync "$@")

  # 本来の rsync の出力を表示
  echo ""
  printf "\e[36;40;1m=== Rsync の全出力 ===\e[m\n"
  echo ""
  echo "$rsync_output"

  # ファイルだけの出力を表示（ディレクトリを除外）
  echo ""
  printf "\e[36;40;1m=== スラッシュで終わる、ディレクトリを除外 ===\e[m\n"
  echo ""
  echo "$rsync_output" | grep -v '/$'
}


if [ -d $dir ]; then
  if [[ $mode != "PRODUCTION" && $mode != *_PRODUCTION && $force_run == "force" ]]; then
    myrsync $rsync_opt -e ssh $RSYNC_LOCAL_DIR ${rsync_remote_ssh_alias}:${rsync_remote_dir}
  else
    echo "---------- dry-run ----------"
    myrsync $rsync_opt --dry-run -e ssh $RSYNC_LOCAL_DIR ${rsync_remote_ssh_alias}:${rsync_remote_dir}
    echo "---------- exec OK? ----------"
    /bin/echo -n "Y/n: "
    read ans
    if [ $ans == "Y" ]; then
      myrsync $rsync_opt -e ssh $RSYNC_LOCAL_DIR ${rsync_remote_ssh_alias}:${rsync_remote_dir}
    else
      printf "\e[37;41;1m Stop \e[m\n"
      exit 0
    fi
  fi
fi

if [[ $mode == "PRODUCTION" || $mode == *_PRODUCTION ]]; then
  ssh $rsync_remote_ssh_alias "cd $rsync_remote_dir && \
    /usr/bin/php8.2 composer.phar install --optimize-autoloader --no-dev && \
    /usr/bin/php8.2 artisan migrate --force && \
    /usr/bin/php8.2 artisan db:seed --force && \
    /usr/bin/php8.2 artisan optimize"

  echo npm run prod も行いますか？
  /bin/echo -n "Y/n: "
  read ans
  if [ "$ans" = "Y" ]; then
    ssh $rsync_remote_ssh_alias "cd $rsync_remote_dir && npm run prod"
  fi
else
  ssh $rsync_remote_ssh_alias "cd $rsync_remote_dir && \
    /usr/bin/php8.2 composer.phar install && \
    /usr/bin/php8.2 artisan migrate && \
    /usr/bin/php8.2 artisan db:seed && \
    /usr/bin/php8.2 artisan optimize:clear"

  echo npm run dev も行いますか？
  /bin/echo -n "Y/n: "
  read ans
  if [ "$ans" = "Y" ]; then
    ssh $rsync_remote_ssh_alias "cd $rsync_remote_dir && npm run dev"
  fi
fi

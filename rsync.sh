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

# production の場合は一度確認を挟む
if [ $mode == "PRODUCTION" ]; then
  echo "---------- production !!!!!!!!!!!!!!!!! OK? ----------"
  /bin/echo -n "Y/n: "
  read ans
  if [ $ans != "Y" ]; then
    echo "Stop"
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

rsync_opt="-v --checksum --archive --delete --exclude-from=rsync_exclude.txt"
if [ -d $dir ]; then
  echo "---------- dry-run ----------"
  rsync $rsync_opt --dry-run -e ssh $RSYNC_LOCAL_DIR ${rsync_remote_ssh_alias}:${rsync_remote_dir}
  echo "---------- exec OK? ----------"
  /bin/echo -n "Y/n: "
  read ans
  if [ $ans == "Y" ]; then
    rsync $rsync_opt -e ssh $RSYNC_LOCAL_DIR ${rsync_remote_ssh_alias}:${rsync_remote_dir}
  else
    echo "Stop"
    exit 0
  fi
fi

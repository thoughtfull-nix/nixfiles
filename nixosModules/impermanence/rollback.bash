echo "Impermanence starting..."
# take snapshot of root
mkdir /btrfs_tmp
echo "Using device @device@..."
echo "Using snapshots subvolume @snapshots@..."
mount @device@ /btrfs_tmp
if [ -e /btrfs_tmp/root ]; then
  echo "Taking snapshot of root..."
  mkdir -p /btrfs_tmp/@snapshots@
  lastmod=$(stat -c %Y /btrfs_tmp/root)
  timestamp=$(date --date="@$lastmod" "+%FT%T")
  mv /btrfs_tmp/root "/btrfs_tmp/@snapshots@/$timestamp"
fi

# delete snapshots older than 30 days
delete_subvolume_recursively() {
  echo "Recursively deleting subvolume $1..."
  IFS="
"
  for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
    delete_subvolume_recursively "/btrfs_tmp/$i"
  done
  btrfs subvolume delete "$1"
}

# shellcheck disable=SC2044
for i in $(find /btrfs_tmp/@snapshots@/* -maxdepth 0 -mtime +30); do
  echo "Deleting old root $i..."
  delete_subvolume_recursively "$i"
done

# create new empty subvolume
echo "Creating new root..."
btrfs subvolume create /btrfs_tmp/root
umount /btrfs_tmp
echo "Impermanence done"

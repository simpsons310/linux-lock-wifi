# wifi-ap — khoá Wi-Fi vào một điểm phát

Script Bash nhỏ dùng `nmcli` (NetworkManager) để:

- xem các điểm phát (access point, BSSID) của mạng Wi-Fi đang dùng: băng tần, kênh, tín hiệu, bảo mật;
- **khoá** một profile Wi-Fi vào một điểm phát cụ thể, để máy không tự chuyển qua lại giữa các điểm phát (roaming) rồi rớt mạng;
- bỏ khoá để máy quay lại roaming bình thường.

Script phù hợp với các mạng có nhiều điểm phát cùng tên (quán café, văn phòng, mesh) mà laptop Linux cứ kết nối được vài giây là mất, trong khi các máy khác dùng bình thường.

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
  - [1.1. Triệu chứng](#11-triệu-chứng)
  - [1.2. Nguyên nhân thường gặp](#12-nguyên-nhân-thường-gặp)
  - [1.3. Hướng xử lý](#13-hướng-xử-lý)
- [2. Cài đặt](#2-cài-đặt)
  - [2.1. Phụ thuộc](#21-phụ-thuộc)
  - [2.2. Cài script](#22-cài-script)
- [3. Cách dùng](#3-cách-dùng)
  - [3.1. Ví dụ](#31-ví-dụ)
  - [3.2. Khi nào cần bỏ khoá](#32-khi-nào-cần-bỏ-khoá)
- [4. Cách hoạt động](#4-cách-hoạt-động)
- [5. Khắc phục sự cố](#5-khắc-phục-sự-cố)
  - [5.1. Tắt PMF cho profile](#51-tắt-pmf-cho-profile)
  - [5.2. Tắt tiết kiệm năng lượng Wi-Fi](#52-tắt-tiết-kiệm-năng-lượng-wi-fi)
  - [5.3. Đặt mã quốc gia](#53-đặt-mã-quốc-gia)
  - [5.4. Hướng xa hơn](#54-hướng-xa-hơn)
  - [5.5. Lệnh chẩn đoán](#55-lệnh-chẩn-đoán)
- [6. TODO](#6-todo)
  - [6.1. Lệnh mới](#61-lệnh-mới)
  - [6.2. Giao diện terminal mượt hơn](#62-giao-diện-terminal-mượt-hơn)
  - [6.3. Giao diện trên GNOME](#63-giao-diện-trên-gnome)
  - [6.4. Tự động khoá](#64-tự-động-khoá)

---

## 1. Bối cảnh

### 1.1. Triệu chứng

Trên một mạng có nhiều điểm phát cùng SSID, máy kết nối vài giây rồi mất, lặp đi lặp lại. Các thiết bị khác vẫn ổn, và chính máy đó vẫn dùng ổn ở mạng khác (mạng nhà, hotspot điện thoại). Log NetworkManager thường lặp lại các dòng sau:

```txt
Activation: (wifi) association took too long, failing activation
state change: config -> failed (reason 'ssid-not-found')
Activation: (wifi) disconnected during association, retrying connection
```

### 1.2. Nguyên nhân thường gặp

- **Máy liên tục chuyển điểm phát.** wpa_supplicant được cấu hình quét nền (`bgscan`), ví dụ `simple:30:-65:300`: khi tín hiệu yếu hơn ngưỡng (-65 dBm) thì 30 giây quét một lần để tìm điểm phát tốt hơn. Nếu tín hiệu điểm đang dùng dao động ngay quanh ngưỡng, máy sẽ chuyển qua chuyển lại liên tục.
- **Driver xử lý roaming kém.** Với một số card (đã gặp trên MediaTek MT7921/MT7922, driver `mt7921e`), mỗi lần chuyển điểm phát là một lần rớt mạng.
- **Hệ thống mạng tự điều phối thiết bị (band/client steering).** Một số hệ thống Wi-Fi doanh nghiệp, ví dụ Aruba ClientMatch, tự chỉ định mỗi thiết bị vào một điểm phát; các điểm phát khác sẽ lờ yêu cầu kết nối của thiết bị đó. Dấu hiệu:
  - khoá vào một điểm phát khác thì log lặp `authenticating -> disconnected` sau khoảng 5 giây rồi bỏ cuộc;
  - log wpa_supplicant đều đặn có dòng `RRM: ... radio measurement ...`, tức router liên tục yêu cầu thiết bị đo sóng;
  - chỉ khoá vào đúng điểm phát mà hệ thống đang cấp cho máy thì mới giữ được kết nối.

  Đây là giả thuyết rút ra từ log, chưa được xác nhận chắc chắn.

### 1.3. Hướng xử lý

1. Kết nối bình thường.
2. Khoá vào **điểm phát đang kết nối** (dòng `● connected` trong bảng) để máy thôi chuyển điểm phát.
3. Chỉ chọn điểm phát mạnh nhất (`lock -b`) khi mạng **không** tự điều phối thiết bị. Nếu mạng có điều phối, điểm phát mạnh nhất có thể từ chối kết nối.

---

## 2. Cài đặt

### 2.1. Phụ thuộc

Cần có: `bash`, `networkmanager` (`nmcli`). `fzf` chỉ cần cho các thao tác chọn tương tác (menu, `lock` không có `-b`).

```bash
# Arch
sudo pacman -S --needed networkmanager fzf
# Debian/Ubuntu
sudo apt install network-manager fzf
```

### 2.2. Cài script

Cài script vào `PATH` với tên `wifi-ap`:

```bash
mkdir -p ~/.local/bin
install -m 755 lock-wifi.sh ~/.local/bin/wifi-ap
```

Nếu `~/.local/bin` chưa có trong `PATH`:

```bash
# bash/zsh: thêm vào ~/.bashrc hoặc ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
# fish
fish_add_path ~/.local/bin
```

Trên hầu hết các bản desktop, user đang đăng nhập được polkit cho phép sửa profile Wi-Fi nên không cần `sudo`. Nếu script báo `failed to set lock`, hãy chạy lại với `sudo`.

---

## 3. Cách dùng

```txt
wifi-ap                      menu chọn lệnh (fzf)
wifi-ap status [CONN]        kết nối hiện tại, điểm phát đang dùng, trạng thái khoá
wifi-ap list   [-a] [CONN]   bảng điểm phát của mạng (-a: mọi mạng xung quanh)
wifi-ap lock   [-b] [CONN]   chọn điểm phát để khoá (-b: khoá luôn điểm mạnh nhất)
wifi-ap unlock [CONN]        bỏ khoá, quay lại roaming bình thường
wifi-ap help                 in hướng dẫn
```

`CONN` là tên profile NetworkManager (xem bằng `nmcli connection show`). Nếu bỏ trống, script dùng profile Wi-Fi đang kết nối.

### 3.1. Ví dụ

Xem các điểm phát của mạng đang dùng:

```txt
$ wifi-ap list
Connection : MyCafe
SSID       : MyCafe
Connected  : AA:BB:CC:00:00:04
Locked to  : not locked (free roaming)

Scanning...
BSSID              BAND      CH  SIGNAL      SECURITY      SSID
AA:BB:CC:00:00:01  5GHz      52  █████  92%  WPA2 WPA3     MyCafe
AA:BB:CC:00:00:02  2.4GHz     6  ████░  84%  WPA2 WPA3     MyCafe
AA:BB:CC:00:00:04  5GHz     149  ███░░  60%  WPA2 WPA3     MyCafe   ● connected
```

Bảng xếp theo tín hiệu từ mạnh đến yếu (tính bằng %, theo `nmcli`). `● connected` là điểm phát đang dùng, `◆ locked` là điểm phát đã khoá.

Khoá vào một điểm phát (chọn trong fzf, Enter để xác nhận, Esc để huỷ):

```bash
wifi-ap lock
```

Khoá luôn vào điểm phát mạnh nhất, không cần chọn:

```bash
wifi-ap lock -b
```

Sau khi khoá, script kết nối lại ngay. Nếu không vào được điểm phát vừa chọn, hãy chạy `wifi-ap unlock`.

Bỏ khoá cho một profile khi đang ở mạng khác:

```bash
wifi-ap unlock "MyCafe"
```

Nếu đang không có Wi-Fi, `wifi-ap unlock` không kèm tên sẽ liệt kê các profile đang bị khoá để bạn chọn.

### 3.2. Khi nào cần bỏ khoá

- Không vào được mạng đó nữa: điểm phát đã khoá bị tắt hoặc ngoài tầm.
- Lần sau có thể ngồi ở vị trí khác trong cùng khu vực.
- Sau khi cập nhật kernel hoặc firmware, để thử xem lỗi roaming đã được sửa chưa.

Khi đổi chỗ ngồi thì không cần bỏ khoá: chạy `lock` lại, khoá mới sẽ ghi đè khoá cũ.

Khoá gắn với **từng profile**, không ảnh hưởng tới các mạng khác.

---

## 4. Cách hoạt động

- **Khoá** là đặt thuộc tính `802-11-wireless.bssid` của profile rồi kết nối lại:

  ```bash
  nmcli connection modify "MyCafe" 802-11-wireless.bssid AA:BB:CC:00:00:04
  nmcli connection up "MyCafe"
  ```

  Khi profile có BSSID, wpa_supplicant chỉ kết nối vào đúng điểm phát đó và không roaming.

- **Bỏ khoá** là đặt `802-11-wireless.bssid ""`, có hiệu lực từ lần kết nối sau.
- **Quét** bằng `nmcli -t -f IN-USE,BSSID,SSID,CHAN,FREQ,SIGNAL,SECURITY dev wifi list --rescan yes`. Nếu không được phép quét lại, script dùng kết quả quét gần nhất.
- Trong output `-t`, nmcli escape dấu `:` thành `\:`. Script đổi tạm sang ký tự `\x1f` trước khi tách cột rồi khôi phục lại, nên tên mạng có dấu `:` vẫn hiển thị đúng.
- Điểm phát được lọc theo SSID **khớp chính xác**, nên `MyCafe` không lẫn với `MyCafe 2`.

---

## 5. Khắc phục sự cố

Nếu đã khoá mà vẫn rớt mạng, có thể thử thêm các cách sau.

### 5.1. Tắt PMF cho profile

```bash
nmcli connection modify "MyCafe" 802-11-wireless-security.pmf 1   # 1 = tắt
```

### 5.2. Tắt tiết kiệm năng lượng Wi-Fi

Một số driver (ví dụ `mt7921e`) hay rớt mạng khi bật power save. Tạo file `/etc/NetworkManager/conf.d/wifi-powersave.conf`:

```ini
[connection]
wifi.powersave = 2
```

Các giá trị: `0` mặc định, `1` không can thiệp, `2` tắt, `3` bật. Áp dụng bằng `sudo systemctl restart NetworkManager`, rồi kiểm tra bằng `iw dev <iface> get power_save` (phải ra `off`).

`sudo iw dev <iface> set power_save off` chỉ có tác dụng tạm thời và bị ghi đè mỗi lần kết nối lại.

### 5.3. Đặt mã quốc gia

Đặt đúng mã quốc gia giúp máy dùng đúng các kênh được phép (kể cả kênh DFS ở 5GHz). Ví dụ trên Arch:

```bash
sudo pacman -S --needed wireless-regdb
# bỏ dấu # trước dòng WIRELESS_REGDOM="<mã nước>" trong /etc/conf.d/wireless-regdom
sudo iw reg set <mã nước>   # ví dụ: VN, US, DE
iw reg get
```

Nếu `iw reg get` vẫn ra `country 00`, hãy khởi động lại máy.

### 5.4. Hướng xa hơn

- Dùng `iwd` thay wpa_supplicant làm backend Wi-Fi của NetworkManager (`iwd` thường roaming tốt hơn).
- Thay card Wi-Fi (ví dụ Intel AX210/BE200) nếu card là loại M.2 tháo được.

### 5.5. Lệnh chẩn đoán

```bash
# tên interface Wi-Fi
nmcli device status

# kết nối hiện tại: điểm phát, tần số, tín hiệu (dBm), tốc độ
iw dev <iface> link

# quét điểm phát của một mạng, tín hiệu tính bằng dBm (cần sudo)
sudo iw dev <iface> scan | grep -E '^BSS|SSID:|signal:|freq:' | grep -B3 '<SSID>'

# cấu hình bảo mật từng điểm phát
sudo iw dev <iface> scan | grep -E '^BSS|SSID:|freq:|Authentication suites|Capabilities:.*MFP' | grep -B1 -A3 '<SSID>'

# log ngay sau một lần kết nối thất bại
journalctl -u NetworkManager -n 60 --no-pager
journalctl -u wpa_supplicant -n 40 --no-pager

# theo dõi log trực tiếp
journalctl -fu NetworkManager

# driver và firmware
lspci -k | grep -A3 -i network
```

Log thất bại điển hình khi điểm phát lờ yêu cầu kết nối:

```txt
Config: added 'bssid' value 'AA:BB:CC:00:00:01'
supplicant interface state: inactive -> authenticating
supplicant interface state: authenticating -> disconnected     # sau ~5 giây
... lặp vài lần ...
Activation: (wifi) association took too long, failing activation
```

---

## 6. TODO

### 6.1. Lệnh mới

- [ ] `wifi-ap lock -c`: khoá luôn vào điểm phát đang kết nối, không cần chọn.
- [ ] `wifi-ap locked`: liệt kê nhanh các profile đang bị khoá.
- [ ] `wifi-ap unlock`: khi mạng hiện tại không bị khoá, liệt kê các profile đang khoá để chọn (hiện chỉ làm vậy khi không có Wi-Fi).

### 6.2. Giao diện terminal mượt hơn

- [ ] Hiện spinner hoặc tiến độ trong lúc quét, thay cho dòng `Scanning...`.
- [ ] Con trỏ fzf mặc định nằm ở dòng `● connected` thay vì dòng mạnh nhất.
- [ ] Phím tắt trong fzf để quét lại và làm mới danh sách (`--bind ctrl-r:reload(...)`) mà không phải thoát ra.
- [ ] Ô preview trong fzf hiện chi tiết điểm phát: tín hiệu dBm, kênh DFS, chuẩn bảo mật, PMF.
- [ ] Tô màu theo băng tần và mức tín hiệu, tự tắt màu khi output không phải terminal (`NO_COLOR`, `! -t 1`).
- [ ] Hỏi xác nhận trước khi khoá vì máy sẽ mất kết nối vài giây; hiện tiến độ kết nối lại.

### 6.3. Giao diện trên GNOME

- [ ] Extension GNOME Shell thêm mục vào Quick Settings: xem điểm phát, khoá/bỏ khoá chỉ bằng một cú nhấp, hiện biểu tượng khi profile đang bị khoá.
- [ ] Hoặc một ứng dụng nhỏ GTK4/libadwaita gọi lại `wifi-ap` (hay dùng thẳng D-Bus của NetworkManager).
- [ ] Thông báo desktop (`notify-send`) khi khoá/bỏ khoá xong hoặc khi kết nối lại thất bại.

### 6.4. Tự động khoá

Dùng NetworkManager dispatcher (`/etc/NetworkManager/dispatcher.d/`) để tự khoá khi kết nối vào các mạng có trong danh sách (`wifi-ap auto add/remove/list`). Cần xử lý ba vấn đề:

1. **Vòng lặp vô hạn:** khoá buộc máy kết nối lại, dispatcher lại chạy và lại khoá. Cần cờ "vừa khoá xong" để bỏ qua lần chạy đó.
2. **Khoá cũ thành bẫy:** lần sau ngồi ở chỗ khác, điểm phát cũ ngoài tầm nên không kết nối được. Cần tự bỏ khoá khi ngắt kết nối.
3. **Quyền root:** dispatcher chạy với quyền root, nên script chỉ được sửa các profile có trong danh sách.

Với mạng tự điều phối thiết bị, chế độ tự động nên khoá vào điểm phát đang được cấp chứ không phải điểm phát mạnh nhất.

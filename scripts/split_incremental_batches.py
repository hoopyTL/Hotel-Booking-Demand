"""
Script tách file tĩnh hotel_bookings.csv thành các batch theo năm nhận phòng
để mô phỏng Full Load (2015-2016) và Incremental Load (2017) trên SSIS.
Sử dụng thư viện chuẩn Python (csv).
Chạy: python3 scripts/split_incremental_batches.py
"""

import argparse
import csv
from pathlib import Path


def split_batches(input_csv: Path, out_dir: Path) -> None:
    if not input_csv.exists():
        print(f"[!] Không tìm thấy file nguồn: {input_csv}")
        return

    out_dir.mkdir(parents=True, exist_ok=True)
    init_path = out_dir / "batch_01_initial_2015_2016.csv"
    inc_path = out_dir / "batch_02_incremental_2017.csv"

    init_count = 0
    inc_count = 0

    with (
        input_csv.open("r", encoding="utf-8", newline="") as fin,
        init_path.open("w", encoding="utf-8", newline="") as f_init,
        inc_path.open("w", encoding="utf-8", newline="") as f_inc,
    ):
        reader = csv.DictReader(fin)
        fieldnames = reader.fieldnames or []

        w_init = csv.DictWriter(f_init, fieldnames=fieldnames, lineterminator="\n")
        w_inc = csv.DictWriter(f_inc, fieldnames=fieldnames, lineterminator="\n")
        w_init.writeheader()
        w_inc.writeheader()

        for row in reader:
            yr = row.get("arrival_date_year", "")
            if yr in ("2015", "2016"):
                w_init.writerow(row)
                init_count += 1
            elif yr == "2017":
                w_inc.writerow(row)
                inc_count += 1

    print(f"[+] Đã tạo {init_path} ({init_count:,} dòng)")
    print(f"[+] Đã tạo {inc_path} ({inc_count:,} dòng)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Tách CSV thành các batch cho SSIS")
    parser.add_argument("--input", type=Path, default=Path("data/raw/hotel_bookings.csv"))
    parser.add_argument("--out-dir", type=Path, default=Path("data/batches"))
    args = parser.parse_args()
    split_batches(args.input, args.out_dir)

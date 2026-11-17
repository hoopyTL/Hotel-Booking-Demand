"""
Data Profiling script cho bộ dữ liệu Hotel Booking Demand (hotel_bookings.csv).
Sử dụng thư viện chuẩn Python (csv, collections, statistics) — chạy ngay không cần cài đặt thêm package.
Chạy: python3 scripts/data_profiling.py --input data/raw/hotel_bookings.csv
"""

import argparse
import csv
from collections import Counter
from datetime import date, datetime
from pathlib import Path
import statistics

MONTH_MAP = {
    "January": 1, "February": 2, "March": 3, "April": 4,
    "May": 5, "June": 6, "July": 7, "August": 8,
    "September": 9, "October": 10, "November": 11, "December": 12,
}


def run_profiling(csv_path: Path) -> None:
    if not csv_path.exists():
        print(f"[!] Không tìm thấy file tại: {csv_path}")
        return

    with csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames or []

        total_rows = 0
        seen_rows = set()
        duplicate_rows = 0

        na_counts = Counter()
        null_counts = Counter()
        undefined_counts = Counter()

        hotel_counts = Counter()
        status_cross = Counter()
        meal_counts = Counter()
        segment_counts = Counter()
        channel_counts = Counter()
        deposit_counts = Counter()
        customer_counts = Counter()

        adr_values = []
        adr_negative_rows = []
        adr_zero_count = 0
        adr_gt_1000_rows = []

        zero_guests_count = 0
        zero_adults_with_kids_count = 0
        max_adults = (0, 0)
        max_children = (0, 0)
        max_babies = (0, 0)

        zero_nights_total = 0
        zero_nights_checked_out = 0
        room_changed_count = 0

        min_arrival_date = None
        max_arrival_date = None
        invalid_dates = 0
        canceled_after_arrival = 0

        for idx, row in enumerate(reader, start=1):
            total_rows += 1
            row_tuple = tuple(row[c] for c in columns)
            if row_tuple in seen_rows:
                duplicate_rows += 1
            else:
                seen_rows.add(row_tuple)

            for c in columns:
                val = (row[c] or "").strip()
                if val == "":
                    null_counts[c] += 1
                elif val.upper() in ("NA", "NULL"):
                    na_counts[c] += 1
                elif val == "Undefined":
                    undefined_counts[c] += 1

            hotel_counts[row["hotel"]] += 1
            status_cross[(row["is_canceled"], row["reservation_status"])] += 1
            meal_counts[row["meal"]] += 1
            segment_counts[row["market_segment"]] += 1
            channel_counts[row["distribution_channel"]] += 1
            deposit_counts[row["deposit_type"]] += 1
            customer_counts[row["customer_type"]] += 1

            # ADR
            try:
                adr = float(row["adr"])
                adr_values.append(adr)
                if adr < 0:
                    adr_negative_rows.append((idx, adr, row["hotel"], row["reservation_status"]))
                elif adr == 0:
                    adr_zero_count += 1
                elif adr > 1000:
                    adr_gt_1000_rows.append((idx, adr, row["hotel"], row["reservation_status"]))
            except ValueError:
                pass

            # Guests
            adults = int(row["adults"]) if row["adults"].isdigit() else 0
            children = int(float(row["children"])) if row["children"] not in ("NA", "", "NULL") else 0
            babies = int(row["babies"]) if row["babies"].isdigit() else 0
            total_guests = adults + children + babies

            if total_guests == 0:
                zero_guests_count += 1
            elif adults == 0 and (children > 0 or babies > 0):
                zero_adults_with_kids_count += 1

            if adults > max_adults[0]:
                max_adults = (adults, idx)
            if children > max_children[0]:
                max_children = (children, idx)
            if babies > max_babies[0]:
                max_babies = (babies, idx)

            # Nights
            wknd = int(row["stays_in_weekend_nights"])
            wk = int(row["stays_in_week_nights"])
            if wknd + wk == 0:
                zero_nights_total += 1
                if row["reservation_status"] == "Check-Out":
                    zero_nights_checked_out += 1

            # Room change
            if row["reserved_room_type"] != row["assigned_room_type"]:
                room_changed_count += 1

            # Dates
            try:
                arr_dt = date(
                    int(row["arrival_date_year"]),
                    MONTH_MAP[row["arrival_date_month"]],
                    int(row["arrival_date_day_of_month"]),
                )
                if min_arrival_date is None or arr_dt < min_arrival_date:
                    min_arrival_date = arr_dt
                if max_arrival_date is None or arr_dt > max_arrival_date:
                    max_arrival_date = arr_dt

                stat_dt = datetime.strptime(row["reservation_status_date"], "%Y-%m-%d").date()
                if row["reservation_status"] == "Canceled" and stat_dt > arr_dt:
                    canceled_after_arrival += 1
            except Exception:
                invalid_dates += 1

    print("=" * 80)
    print(f"BÁO CÁO DATA PROFILING THỰC TẾ: {csv_path}")
    print("=" * 80)
    print(f"- Tổng số bản ghi (Rows)         : {total_rows:,}")
    print(f"- Tổng số thuộc tính (Columns)   : {len(columns)}")
    print(f"- Khoảng ngày nhận phòng         : {min_arrival_date} -> {max_arrival_date}")
    print(f"- Phân bố theo khách sạn         : {dict(hotel_counts)}")
    print(f"- Bản ghi trùng lặp hoàn toàn    : {duplicate_rows:,} ({duplicate_rows/total_rows*100:.2f}%)")
    print(f"- Bản ghi duy nhất (Distinct)    : {len(seen_rows):,}")

    print("\n1. KIỂM TRA MISSING / 'NA' / 'NULL' TRÊN CÁC CỘT:")
    for c in columns:
        if na_counts[c] > 0 or null_counts[c] > 0:
            print(
                f"   - {c:<28}: Chuỗi 'NA'/'NULL' = {na_counts[c]:>7,} ({na_counts[c]/total_rows*100:.3f}%)"
                f" | Rỗng = {null_counts[c]}"
            )

    print("\n2. KIỂM TRA GIÁ TRỊ 'Undefined' TRONG CÁC CỘT PHÂN LOẠI:")
    for c in columns:
        if undefined_counts[c] > 0:
            print(f"   - {c:<28}: {undefined_counts[c]:>7,} dòng ({undefined_counts[c]/total_rows*100:.3f}%)")

    print("\n3. KIỂM TRA BẤT THƯỜNG GIÁ PHÒNG (ADR):")
    print(
        f"   - Min = {min(adr_values):.2f} | Max = {max(adr_values):.2f} "
        f"| Mean = {statistics.mean(adr_values):.2f} | Median = {statistics.median(adr_values):.2f}"
    )
    print(f"   - ADR < 0 (Lỗi âm)            : {len(adr_negative_rows):>7,} dòng -> {adr_negative_rows}")
    print(f"   - ADR = 0 (Miễn phí/Compl.)   : {adr_zero_count:>7,} dòng ({adr_zero_count/total_rows*100:.2f}%)")
    print(f"   - ADR > 1000 (Outlier cực đại): {len(adr_gt_1000_rows):>7,} dòng -> {adr_gt_1000_rows}")

    print("\n4. KIỂM TRA BẤT THƯỜNG SỐ KHÁCH & LƯU TRÚ:")
    print(f"   - Tổng khách = 0 (adults+children+babies=0)        : {zero_guests_count:>7,} dòng")
    print(f"   - Chỉ có trẻ em/em bé (adults=0 & kids>0)          : {zero_adults_with_kids_count:>7,} dòng")
    print(f"   - Max adults = {max_adults[0]} (dòng {max_adults[1]}), Max children = {max_children[0]} (dòng {max_children[1]}), Max babies = {max_babies[0]} (dòng {max_babies[1]})")
    print(f"   - Tổng số đêm = 0 (weekend+week=0)                 : {zero_nights_total:>7,} dòng (trong đó Check-Out: {zero_nights_checked_out:,})")
    print(f"   - Đổi hạng phòng (reserved_room != assigned_room)  : {room_changed_count:>7,} dòng ({room_changed_count/total_rows*100:.2f}%)")

    print("\n5. KIỂM TRA TÍNH NHẤT QUÁN TRẠNG THÁI & NGÀY THÁNG:")
    print(f"   - Lỗi định dạng ngày tháng                         : {invalid_dates:>7,} dòng")
    print(f"   - Đối chiếu (is_canceled, reservation_status)      : {dict(status_cross)}")
    print(f"   - Canceled có status_date > arrival_date           : {canceled_after_arrival:>7,} dòng")

    print("\n6. PHÂN BỐ CÁC CHIỀU PHÂN LOẠI CHÍNH:")
    print(f"   - meal                 : {dict(meal_counts)}")
    print(f"   - market_segment       : {dict(segment_counts)}")
    print(f"   - distribution_channel : {dict(channel_counts)}")
    print(f"   - deposit_type         : {dict(deposit_counts)}")
    print(f"   - customer_type        : {dict(customer_counts)}")
    print("=" * 80)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Chạy Data Profiling trên hotel_bookings.csv")
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("data/raw/hotel_bookings.csv"),
        help="Đường dẫn tới file hotel_bookings.csv",
    )
    args = parser.parse_args()
    run_profiling(args.input)

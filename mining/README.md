# Báo cáo Kết quả Data Mining — Hotel Booking Demand (`mining/`)

Dữ liệu đầu vào được trích xuất trực tiếp từ kho dữ liệu **SQL Server `HotelBooking_DW` (`dw.Fact_Hotel_Booking` JOIN `dw.Dim_*`, `119,389` giao dịch)** và kết quả khai phá được lưu ngược về schema **`[mining]`** trên SQL Server.

---

## 1. Classification — Dự đoán Hủy phòng (`is_canceled`)

* **Tập dữ liệu:** 80% Train (`95,511` dòng) / 20% Test (`23,878` dòng), chia tầng (Stratified) theo `is_canceled`, loại bỏ hoàn toàn các cột rò rỉ dữ liệu (`reservation_status`, `actual_revenue`, `lost_revenue`).
* **Mô hình tốt nhất:** **`Random Forest (150 trees)`**

| model_name | accuracy | precision | recall | f1_score | roc_auc | train_rows | test_rows |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Logistic Regression | 0.8116 | 0.808 | 0.6447 | 0.7171 | 0.8911 | 95511 | 23878 |
| Decision Tree (max_depth=10) | 0.8373 | 0.8113 | 0.7308 | 0.769 | 0.9144 | 95511 | 23878 |
| Random Forest (150 trees) | 0.8585 | 0.8669 | 0.73 | 0.7926 | 0.9354 | 95511 | 23878 |

### Top 10 yếu tố quyết định khả năng hủy phòng (Feature Importance)

| rank_no | feature_name | importance |
| --- | --- | --- |
| 1 | deposit_type_No Deposit | 0.14352067276694888 |
| 2 | deposit_type_Non Refund | 0.13068838562216073 |
| 3 | is_portugal | 0.11647832063201377 |
| 4 | lead_time | 0.09484458565462649 |
| 5 | total_of_special_requests | 0.06755779918548555 |
| 6 | previous_cancellations | 0.053779040165452145 |
| 7 | is_room_changed | 0.050424850707316546 |
| 8 | market_segment_name_Online TA | 0.044193489683491065 |
| 9 | required_car_parking_spaces | 0.03506387574872094 |
| 10 | adr | 0.03137857354724178 |

* Biểu đồ: `mining/outputs/01_classification_roc_and_cm.png`, `mining/outputs/02_feature_importance.png`
* Bảng SQL kết quả: `[mining].[model_evaluation_metrics]`, `[mining].[feature_importance]`, `[mining].[booking_cancellation_predictions]` (`23,878` bản ghi test kèm xác suất hủy & nhãn `Low / Medium / High Risk`).

---

## 2. Clustering — Phân cụm Khách hàng (`K-Means`, K = 4)

* **Chỉ số Silhouette theo số cụm K:** `{3: 0.2287, 4: 0.1989, 5: 0.1984, 6: 0.2122}`

| cluster_id | cluster_label | booking_count | avg_lead_time | avg_total_nights | avg_adr | cancel_rate_pct | total_actual_revenue | total_lost_revenue |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | Premium & Leisure Long-Stay | 30494 | 78.05 | 3.87 | 151.84 | 29.95 | 11827761.3 | 6201220.26 |
| 1 | Short-Stay & Last-Minute | 59345 | 46.71 | 2.59 | 83.57 | 31.52 | 8229574.0 | 4680877.01 |
| 2 | Early-Bird & Group Planners | 29404 | 245.97 | 4.66 | 86.86 | 55.23 | 5938514.79 | 5813946.25 |
| 3 | High-Risk Repeat Cancellers | 145 | 229.7 | 3.87 | 58.15 | 99.31 | 474.12 | 25793.6 |

* Biểu đồ: `mining/outputs/03_customer_clusters.png`
* Bảng SQL kết quả: `[mining].[customer_clusters_summary]`

---

## 3. Association Rules — Khai phá Luật kết hợp (`Apriori`)

Tìm các tổ hợp thuộc tính có mối liên hệ mạnh (`Lift > 1.15`, `Min Support >= 4%`) dẫn đến kết cục `Outcome:Canceled` hoặc `Outcome:Check-Out`:

| antecedent_str | consequent_str | support | confidence | lift |
| --- | --- | --- | --- | --- |
| Customer:Transient + Deposit:Non Refund | Outcome:Canceled | 0.1081 | 1.0 | 2.6996 |
| Customer:Transient + Deposit:Non Refund + SpecialReq:None | Outcome:Canceled | 0.108 | 1.0 | 2.6996 |
| Customer:Transient + Deposit:Non Refund + Room:Same | Outcome:Canceled | 0.1075 | 1.0 | 2.6996 |
| Customer:Transient + Deposit:Non Refund + Segment:Groups | Outcome:Canceled | 0.0667 | 1.0 | 2.6996 |
| Customer:Transient + Deposit:Non Refund + Lead:Long(>90d) | Outcome:Canceled | 0.0841 | 1.0 | 2.6996 |
| Customer:Transient + Deposit:Non Refund + Hotel:City Hotel | Outcome:Canceled | 0.0946 | 1.0 | 2.6996 |
| Deposit:Non Refund + Hotel:City Hotel + Segment:Groups | Outcome:Canceled | 0.0641 | 0.9995 | 2.6982 |
| Deposit:Non Refund + Hotel:City Hotel + Lead:Long(>90d) | Outcome:Canceled | 0.0848 | 0.999 | 2.697 |
| Deposit:Non Refund + Hotel:City Hotel + SpecialReq:None | Outcome:Canceled | 0.1074 | 0.9984 | 2.6952 |
| Deposit:Non Refund + Hotel:City Hotel + Room:Same | Outcome:Canceled | 0.1073 | 0.9984 | 2.6952 |
| Deposit:Non Refund + Hotel:City Hotel | Outcome:Canceled | 0.1076 | 0.9981 | 2.6946 |
| Deposit:Non Refund + Lead:Long(>90d) + Room:Same | Outcome:Canceled | 0.0961 | 0.9957 | 2.6882 |
| Deposit:No Deposit + Room:Changed + SpecialReq:HasReq | Outcome:Check-Out | 0.0522 | 0.9605 | 1.5256 |
| Room:Changed + SpecialReq:HasReq | Outcome:Check-Out | 0.0522 | 0.9604 | 1.5254 |
| Deposit:No Deposit + Room:Changed + Segment:Travel Agency / Operator | Outcome:Check-Out | 0.073 | 0.9558 | 1.5181 |
| Deposit:No Deposit + Hotel:Resort Hotel + Room:Changed | Outcome:Check-Out | 0.0611 | 0.9557 | 1.5181 |
| Room:Changed + Segment:Travel Agency / Operator | Outcome:Check-Out | 0.073 | 0.9539 | 1.5151 |
| Customer:Transient + Room:Changed + Segment:Travel Agency / Operator | Outcome:Check-Out | 0.0547 | 0.9532 | 1.514 |
| Customer:Transient + Deposit:No Deposit + Room:Changed | Outcome:Check-Out | 0.0814 | 0.9526 | 1.513 |
| Deposit:No Deposit + Room:Changed | Outcome:Check-Out | 0.1178 | 0.9511 | 1.5106 |

* Biểu đồ: `mining/outputs/04_association_rules_cancel.png`
* Bảng SQL kết quả: `[mining].[association_rules]`

---

## Cách chạy lại toàn bộ pipeline
```bash
python mining/run_data_mining.py
```

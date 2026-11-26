r"""
Hotel Booking Demand — Data Mining Pipeline (Phase 5)
Reads directly from SQL Server Data Warehouse (.\SQLEXPRESS -> HotelBooking_DW [dw]),
executes 3 core Data Mining tasks:
  1. Classification (Cancellation Prediction: Decision Tree, Logistic Regression, Random Forest)
  2. Clustering (Customer Segmentation: K-Means with Silhouette evaluation)
  3. Association Rules (FP-Growth / Apriori: Root-cause combinations driving Cancellation & Check-Out)
Persists results back into SQL Server ([mining] schema) and generates charts + report.
"""

from pathlib import Path
import warnings

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc
from mlxtend.frequent_patterns import association_rules, fpgrowth
from sklearn.cluster import KMeans
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
    silhouette_score,
)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.tree import DecisionTreeClassifier

warnings.filterwarnings("ignore")

ROOT = Path(r"C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\mining")
OUT_DIR = ROOT / "outputs"
OUT_DIR.mkdir(parents=True, exist_ok=True)

SQL_CONN_STR = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    r"SERVER=.\SQLEXPRESS;"
    "DATABASE=HotelBooking_DW;"
    "Trusted_Connection=yes;"
)


def get_connection() -> pyodbc.Connection:
    # Auto-detect available SQL Server ODBC driver (18, 17, or SQL Server)
    drivers = [d for d in pyodbc.drivers() if "SQL Server" in d]
    for preferred in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server", "SQL Server"):
        if preferred in drivers:
            extra = "Encrypt=no;" if "18" in preferred else ""
            conn_str = (
                f"DRIVER={{{preferred}}};"
                r"SERVER=localhost\SQLEXPRESS;"
                "DATABASE=HotelBooking_DW;"
                f"Trusted_Connection=yes;{extra}"
            )
            return pyodbc.connect(conn_str, timeout=15)
    raise RuntimeError(f"No SQL Server ODBC driver found. Installed drivers: {drivers}")


def load_dw_dataset(conn: pyodbc.Connection) -> pd.DataFrame:
    query = """
    SELECT
        f.booking_sk,
        f.booking_source_id,
        h.hotel_name,
        d.[year] AS arrival_year,
        d.month_number AS arrival_month,
        d.season,
        c.country_iso3,
        ms.market_segment_name,
        ms.segment_group,
        dc.distribution_channel_name,
        rt_res.room_type_code AS reserved_room_type,
        bp.customer_type,
        bp.deposit_type,
        bp.meal_code,
        CAST(bp.is_repeated_guest AS INT) AS is_repeated_guest,
        CAST(rs.is_canceled AS INT) AS is_canceled,
        rs.reservation_status,
        f.lead_time,
        f.stays_in_weekend_nights,
        f.stays_in_week_nights,
        f.total_nights,
        f.adults,
        f.children,
        f.babies,
        f.total_guests,
        CAST(f.adr AS FLOAT) AS adr,
        CAST(f.estimated_revenue AS FLOAT) AS estimated_revenue,
        CAST(f.actual_revenue AS FLOAT) AS actual_revenue,
        CAST(f.lost_revenue AS FLOAT) AS lost_revenue,
        f.booking_changes,
        f.days_in_waiting_list,
        f.required_car_parking_spaces,
        f.total_of_special_requests,
        f.previous_cancellations,
        f.previous_bookings_not_canceled,
        CAST(f.is_room_changed AS INT) AS is_room_changed,
        CAST(f.is_adr_outlier AS INT) AS is_adr_outlier
    FROM dw.Fact_Hotel_Booking f
    JOIN dw.Dim_Hotel h ON f.hotel_key = h.hotel_key
    JOIN dw.Dim_Date d ON f.arrival_date_key = d.date_key
    JOIN dw.Dim_Country c ON f.country_key = c.country_key
    JOIN dw.Dim_Market_Segment ms ON f.market_segment_key = ms.market_segment_key
    JOIN dw.Dim_Distribution_Channel dc ON f.distribution_channel_key = dc.distribution_channel_key
    JOIN dw.Dim_Room_Type rt_res ON f.reserved_room_type_key = rt_res.room_type_key
    JOIN dw.Dim_Booking_Profile bp ON f.booking_profile_key = bp.booking_profile_key
    JOIN dw.Dim_Reservation_Status rs ON f.reservation_status_key = rs.reservation_status_key
    """
    df = pd.read_sql(query, conn)
    print(f"[1/5] Loaded {len(df):,} records from SQL Server HotelBooking_DW (dw.*)")
    return df


# ==============================================================================
# TASK 1: CLASSIFICATION — CANCELLATION PREDICTION (is_canceled)
# ==============================================================================
def run_classification(df: pd.DataFrame):
    print("[2/5] Running Task 1: Classification (Cancellation Prediction)...")
    # Avoid target leakage: exclude reservation_status, actual_revenue, lost_revenue
    num_features = [
        "lead_time",
        "stays_in_weekend_nights",
        "stays_in_week_nights",
        "total_nights",
        "adults",
        "children",
        "babies",
        "adr",
        "booking_changes",
        "days_in_waiting_list",
        "required_car_parking_spaces",
        "total_of_special_requests",
        "previous_cancellations",
        "previous_bookings_not_canceled",
        "is_repeated_guest",
        "is_room_changed",
    ]
    cat_features = [
        "hotel_name",
        "season",
        "market_segment_name",
        "distribution_channel_name",
        "deposit_type",
        "customer_type",
        "meal_code",
        "reserved_room_type",
    ]

    # Top-10 country flag + is_portugal feature (domain-meaningful, compact)
    df_clf = df.copy()
    df_clf["is_portugal"] = (df_clf["country_iso3"] == "PRT").astype(int)
    num_features = num_features + ["is_portugal"]

    X = df_clf[num_features + cat_features]
    y = df_clf["is_canceled"]

    X_train, X_test, y_train, y_test, idx_train, idx_test = train_test_split(
        X, y, df_clf.index, test_size=0.20, random_state=42, stratify=y
    )

    preprocessor = ColumnTransformer(
        transformers=[
            ("num", StandardScaler(), num_features),
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), cat_features),
        ]
    )

    models = {
        "Logistic Regression": LogisticRegression(max_iter=500, random_state=42),
        "Decision Tree (max_depth=10)": DecisionTreeClassifier(max_depth=10, min_samples_leaf=20, random_state=42),
        "Random Forest (150 trees)": RandomForestClassifier(
            n_estimators=150, max_depth=16, min_samples_leaf=5, n_jobs=-1, random_state=42
        ),
    }

    metrics_rows = []
    roc_curves = {}
    best_model_name = None
    best_auc = -1.0
    best_pipe = None
    best_y_pred = None
    best_y_prob = None

    for name, estimator in models.items():
        pipe = Pipeline([("prep", preprocessor), ("clf", estimator)])
        pipe.fit(X_train, y_train)
        y_pred = pipe.predict(X_test)
        y_prob = pipe.predict_proba(X_test)[:, 1]

        acc = accuracy_score(y_test, y_pred)
        prec = precision_score(y_test, y_pred)
        rec = recall_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred)
        auc = roc_auc_score(y_test, y_prob)
        fpr, tpr, _ = roc_curve(y_test, y_prob)
        roc_curves[name] = (fpr, tpr, auc)

        metrics_rows.append({
            "model_name": name,
            "accuracy": round(acc, 4),
            "precision": round(prec, 4),
            "recall": round(rec, 4),
            "f1_score": round(f1, 4),
            "roc_auc": round(auc, 4),
            "train_rows": len(X_train),
            "test_rows": len(X_test),
        })
        print(f"      {name:<30} | Acc={acc:.4f} | Prec={prec:.4f} | Rec={rec:.4f} | F1={f1:.4f} | AUC={auc:.4f}")

        if auc > best_auc:
            best_auc = auc
            best_model_name = name
            best_pipe = pipe
            best_y_pred = y_pred
            best_y_prob = y_prob

    metrics_df = pd.DataFrame(metrics_rows)

    # Feature importance from best tree model (Random Forest)
    prep_fitted = best_pipe.named_steps["prep"]
    clf_fitted = best_pipe.named_steps["clf"]
    feature_names = list(num_features) + list(
        prep_fitted.named_transformers_["cat"].get_feature_names_out(cat_features)
    )
    importances = clf_fitted.feature_importances_
    fi_df = (
        pd.DataFrame({"feature_name": feature_names, "importance": importances})
        .sort_values("importance", ascending=False)
        .head(15)
        .reset_index(drop=True)
    )
    fi_df["rank_no"] = fi_df.index + 1

    # Plot 1: ROC Curve + Model Comparison
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    colors = ["#0F4C81", "#F59E0B", "#0D9488"]
    for (name, (fpr, tpr, auc)), col in zip(roc_curves.items(), colors):
        axes[0].plot(fpr, tpr, label=f"{name} (AUC = {auc:.4f})", linewidth=2.2, color=col)
    axes[0].plot([0, 1], [0, 1], "k--", alpha=0.5)
    axes[0].set_title("ROC Curve — Cancellation Prediction Models", fontweight="bold")
    axes[0].set_xlabel("False Positive Rate")
    axes[0].set_ylabel("True Positive Rate")
    axes[0].legend(loc="lower right", fontsize=9)
    axes[0].grid(alpha=0.25)

    # Confusion Matrix of Best Model
    cm = confusion_matrix(y_test, best_y_pred)
    im = axes[1].imshow(cm, cmap="Blues")
    axes[1].set_title(f"Confusion Matrix — {best_model_name}", fontweight="bold")
    axes[1].set_xticks([0, 1])
    axes[1].set_yticks([0, 1])
    axes[1].set_xticklabels(["Predicted Check-Out", "Predicted Canceled"])
    axes[1].set_yticklabels(["Actual Check-Out", "Actual Canceled"])
    for i in range(2):
        for j in range(2):
            axes[1].text(
                j, i, f"{cm[i, j]:,}",
                ha="center", va="center",
                color="white" if cm[i, j] > cm.max() / 2 else "#0F2942",
                fontsize=12, fontweight="bold"
            )
    fig.colorbar(im, ax=axes[1], fraction=0.046, pad=0.04)
    plt.tight_layout()
    fig.savefig(OUT_DIR / "01_classification_roc_and_cm.png", dpi=160)
    plt.close(fig)

    # Plot 2: Top 15 Feature Importances
    fig, ax = plt.subplots(figsize=(9, 5.5))
    top_fi = fi_df.iloc[::-1]
    ax.barh(top_fi["feature_name"], top_fi["importance"], color="#0F4C81")
    ax.set_title(f"Top 15 Predictors of Hotel Booking Cancellation ({best_model_name})", fontweight="bold")
    ax.set_xlabel("Feature Importance Score")
    ax.grid(axis="x", alpha=0.25)
    plt.tight_layout()
    fig.savefig(OUT_DIR / "02_feature_importance.png", dpi=160)
    plt.close(fig)

    # Score full test set predictions for DB persistence
    pred_df = pd.DataFrame({
        "booking_sk": df_clf.loc[idx_test, "booking_sk"].values,
        "hotel_name": df_clf.loc[idx_test, "hotel_name"].values,
        "market_segment_name": df_clf.loc[idx_test, "market_segment_name"].values,
        "deposit_type": df_clf.loc[idx_test, "deposit_type"].values,
        "actual_canceled": y_test.values,
        "predicted_canceled": best_y_pred,
        "cancel_probability": np.round(best_y_prob, 4),
    })
    pred_df["risk_tier"] = pd.cut(
        pred_df["cancel_probability"],
        bins=[-0.01, 0.30, 0.65, 1.01],
        labels=["Low Risk", "Medium Risk", "High Risk"],
    ).astype(str)

    return metrics_df, fi_df, pred_df, best_model_name


# ==============================================================================
# TASK 2: CLUSTERING — CUSTOMER SEGMENTATION (K-MEANS)
# ==============================================================================
def run_clustering(df: pd.DataFrame):
    print("[3/5] Running Task 2: Clustering (K-Means Customer Segmentation)...")
    # Filter extreme ADR outlier (>1000) so cluster centroids are not distorted
    df_clu = df[df["is_adr_outlier"] == 0].copy()
    cluster_features = [
        "lead_time",
        "total_nights",
        "adr",
        "total_guests",
        "total_of_special_requests",
        "booking_changes",
        "previous_cancellations",
    ]
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(df_clu[cluster_features])

    # Evaluate K=3..6 on a 6,000-row sample for fast Silhouette check
    rng = np.random.RandomState(42)
    sample_idx = rng.choice(len(X_scaled), size=min(6000, len(X_scaled)), replace=False)
    k_candidates = [3, 4, 5, 6]
    inertias = []
    silhouettes = []
    for k in k_candidates:
        km_tmp = KMeans(n_clusters=k, n_init=10, random_state=42)
        labels_tmp = km_tmp.fit_predict(X_scaled[sample_idx])
        inertias.append(km_tmp.inertia_)
        silhouettes.append(silhouette_score(X_scaled[sample_idx], labels_tmp))

    # Fit final K=4 clusters on the full dataset (clean business personas)
    km = KMeans(n_clusters=4, n_init=15, random_state=42)
    df_clu["cluster_id"] = km.fit_predict(X_scaled)

    summary = (
        df_clu.groupby("cluster_id")
        .agg(
            booking_count=("booking_sk", "count"),
            avg_lead_time=("lead_time", "mean"),
            avg_total_nights=("total_nights", "mean"),
            avg_adr=("adr", "mean"),
            avg_total_guests=("total_guests", "mean"),
            avg_special_requests=("total_of_special_requests", "mean"),
            avg_prev_cancels=("previous_cancellations", "mean"),
            cancel_rate_pct=("is_canceled", lambda s: s.mean() * 100.0),
            total_actual_revenue=("actual_revenue", "sum"),
            total_lost_revenue=("lost_revenue", "sum"),
        )
        .reset_index()
    )

    # Assign descriptive business labels deterministically based on cluster characteristics
    labels_map = {}
    remaining = set(summary["cluster_id"])
    # 1. Highest previous_cancellations -> Repeat/Serial Cancellers (or Highest Lead Time if prev_cancels is small)
    c_high_prev = summary.loc[summary["avg_prev_cancels"].idxmax(), "cluster_id"]
    if summary.loc[summary["cluster_id"] == c_high_prev, "avg_prev_cancels"].values[0] > 1.0:
        labels_map[c_high_prev] = "High-Risk Repeat Cancellers"
        remaining.remove(c_high_prev)

    # 2. Highest lead time among remaining -> Early-Bird / Group Planners
    sub = summary[summary["cluster_id"].isin(remaining)]
    c_early = sub.loc[sub["avg_lead_time"].idxmax(), "cluster_id"]
    labels_map[c_early] = "Early-Bird & Group Planners"
    remaining.remove(c_early)

    # 3. Highest ADR or total_nights among remaining -> Premium / Family Leisure Stays
    sub = summary[summary["cluster_id"].isin(remaining)]
    c_prem = sub.loc[(sub["avg_adr"] * sub["avg_total_nights"]).idxmax(), "cluster_id"]
    labels_map[c_prem] = "Premium & Leisure Long-Stay"
    remaining.remove(c_prem)

    # 4. Remaining -> Last-Minute / Short-Stay Guests (or Special-Request Engaged)
    for cid in sorted(remaining):
        row = summary[summary["cluster_id"] == cid].iloc[0]
        if row["avg_special_requests"] >= 1.0:
            labels_map[cid] = "Engaged Low-Risk Guests"
        else:
            labels_map[cid] = "Short-Stay & Last-Minute"

    summary["cluster_label"] = summary["cluster_id"].map(labels_map)
    for col in ["avg_lead_time", "avg_total_nights", "avg_adr", "avg_total_guests",
                "avg_special_requests", "avg_prev_cancels", "cancel_rate_pct"]:
        summary[col] = summary[col].round(2)
    summary["total_actual_revenue"] = summary["total_actual_revenue"].round(2)
    summary["total_lost_revenue"] = summary["total_lost_revenue"].round(2)

    print(summary[["cluster_id", "cluster_label", "booking_count", "avg_lead_time", "avg_adr", "cancel_rate_pct"]].to_string(index=False))

    # Plot 3: Elbow + Cluster Profiles
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    axes[0].plot(k_candidates, silhouettes, marker="o", linewidth=2.2, color="#0D9488")
    axes[0].set_title("K-Means Silhouette Score by Number of Clusters (K)", fontweight="bold")
    axes[0].set_xlabel("Number of Clusters (K)")
    axes[0].set_ylabel("Silhouette Score")
    axes[0].grid(alpha=0.25)

    x_pos = np.arange(len(summary))
    bars = axes[1].bar(x_pos, summary["cancel_rate_pct"], color=["#0F4C81", "#E11D48", "#0D9488", "#F59E0B"])
    axes[1].set_xticks(x_pos)
    axes[1].set_xticklabels(summary["cluster_label"], rotation=15, ha="right", fontsize=8.5)
    axes[1].set_title("Cancellation Rate (%) by Customer Cluster (K=4)", fontweight="bold")
    axes[1].set_ylabel("Cancellation Rate (%)")
    axes[1].set_ylim(0, 105)
    for bar, cnt in zip(bars, summary["booking_count"]):
        h = bar.get_height()
        axes[1].text(bar.get_x() + bar.get_width() / 2, h + 1.5, f"{h:.1f}%\n(n={cnt:,})",
                     ha="center", va="bottom", fontsize=8)
    axes[1].grid(axis="y", alpha=0.25)
    plt.tight_layout()
    fig.savefig(OUT_DIR / "03_customer_clusters.png", dpi=160)
    plt.close(fig)

    return summary, dict(zip(k_candidates, [round(s, 4) for s in silhouettes]))


# ==============================================================================
# TASK 3: ASSOCIATION RULES — APRIORI (FACTORS DRIVING CANCELLATION)
# ==============================================================================
def run_association_rules(df: pd.DataFrame):
    print("[4/5] Running Task 3: Association Rules (Apriori Pattern Mining)...")
    b = pd.DataFrame(index=df.index)
    b["Hotel=" + df["hotel_name"]] = True

    # Build clean binary transaction matrix directly
    items = pd.DataFrame({
        "hotel": "Hotel:" + df["hotel_name"],
        "deposit": "Deposit:" + df["deposit_type"],
        "segment": "Segment:" + df["segment_group"],
        "customer": "Customer:" + df["customer_type"],
        "lead_bucket": pd.cut(
            df["lead_time"],
            bins=[-1, 14, 90, 9999],
            labels=["Lead:Short(<=14d)", "Lead:Medium(15-90d)", "Lead:Long(>90d)"],
        ).astype(str),
        "special_req": np.where(df["total_of_special_requests"] == 0, "SpecialReq:None", "SpecialReq:HasReq"),
        "room_change": np.where(df["is_room_changed"] == 1, "Room:Changed", "Room:Same"),
        "status": np.where(df["is_canceled"] == 1, "Outcome:Canceled", "Outcome:Check-Out"),
    })

    ohe = pd.get_dummies(items, prefix="", prefix_sep="").astype(bool)
    freq = fpgrowth(ohe, min_support=0.05, use_colnames=True, max_len=4)
    rules = association_rules(freq, metric="lift", min_threshold=1.15)

    # Filter rules whose consequent is strictly a single outcome (Outcome:Canceled or Outcome:Check-Out)
    rules["consequent_str"] = rules["consequents"].apply(lambda s: ", ".join(sorted(list(s))))
    rules["antecedent_str"] = rules["antecedents"].apply(lambda s: " + ".join(sorted(list(s))))
    outcome_rules = rules[rules["consequent_str"].isin(["Outcome:Canceled", "Outcome:Check-Out"])].copy()
    outcome_rules = outcome_rules.sort_values(["consequent_str", "lift", "confidence"], ascending=[True, False, False])

    top_cancel = outcome_rules[outcome_rules["consequent_str"] == "Outcome:Canceled"].head(12)
    top_ok = outcome_rules[outcome_rules["consequent_str"] == "Outcome:Check-Out"].head(8)
    final_rules = pd.concat([top_cancel, top_ok], ignore_index=True)
    final_rules = final_rules[["antecedent_str", "consequent_str", "support", "confidence", "lift"]].copy()
    for c in ["support", "confidence", "lift"]:
        final_rules[c] = final_rules[c].round(4)

    print(final_rules.head(10).to_string(index=False))

    # Plot 4: Top Cancellation Association Rules by Lift & Confidence
    fig, ax = plt.subplots(figsize=(10, 5.5))
    plot_r = top_cancel.head(10).iloc[::-1]
    bars = ax.barh(plot_r["antecedent_str"], plot_r["lift"], color="#E11D48")
    ax.set_title("Top 10 Association Rules Driving Booking Cancellation (Sorted by Lift)", fontweight="bold")
    ax.set_xlabel("Lift (> 1.0 = Stronger Positive Association with Cancellation)")
    for bar, conf in zip(bars, plot_r["confidence"]):
        w = bar.get_width()
        ax.text(w + 0.03, bar.get_y() + bar.get_height() / 2, f"Lift={w:.2f} | Conf={conf*100:.1f}%",
                va="center", fontsize=8.5)
    ax.set_xlim(0, plot_r["lift"].max() + 0.85)
    ax.grid(axis="x", alpha=0.25)
    plt.tight_layout()
    fig.savefig(OUT_DIR / "04_association_rules_cancel.png", dpi=160)
    plt.close(fig)

    return final_rules


# ==============================================================================
# PERSIST RESULTS BACK TO SQL SERVER ([mining] SCHEMA)
# ==============================================================================
def save_to_sql_server(
    conn: pyodbc.Connection,
    metrics_df: pd.DataFrame,
    fi_df: pd.DataFrame,
    pred_df: pd.DataFrame,
    clusters_df: pd.DataFrame,
    rules_df: pd.DataFrame,
):
    print("[5/5] Saving Data Mining results into SQL Server schema [mining] ...")
    cur = conn.cursor()
    cur.execute("""
    IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'mining')
        EXEC('CREATE SCHEMA [mining]');

    DROP TABLE IF EXISTS [mining].[model_evaluation_metrics];
    CREATE TABLE [mining].[model_evaluation_metrics] (
        model_name   NVARCHAR(100) NOT NULL,
        accuracy     DECIMAL(6,4)  NOT NULL,
        [precision]  DECIMAL(6,4)  NOT NULL,
        recall       DECIMAL(6,4)  NOT NULL,
        f1_score     DECIMAL(6,4)  NOT NULL,
        roc_auc      DECIMAL(6,4)  NOT NULL,
        train_rows   INT           NOT NULL,
        test_rows    INT           NOT NULL,
        evaluated_at DATETIME2(3)  NOT NULL DEFAULT SYSDATETIME()
    );

    DROP TABLE IF EXISTS [mining].[feature_importance];
    CREATE TABLE [mining].[feature_importance] (
        rank_no      INT           NOT NULL,
        feature_name NVARCHAR(150) NOT NULL,
        importance   DECIMAL(8,6)  NOT NULL
    );

    DROP TABLE IF EXISTS [mining].[booking_cancellation_predictions];
    CREATE TABLE [mining].[booking_cancellation_predictions] (
        booking_sk          BIGINT        NOT NULL PRIMARY KEY,
        hotel_name          VARCHAR(100)  NOT NULL,
        market_segment_name VARCHAR(100)  NOT NULL,
        deposit_type        VARCHAR(50)   NOT NULL,
        actual_canceled     BIT           NOT NULL,
        predicted_canceled  BIT           NOT NULL,
        cancel_probability  DECIMAL(6,4)  NOT NULL,
        risk_tier           VARCHAR(20)   NOT NULL
    );

    DROP TABLE IF EXISTS [mining].[customer_clusters_summary];
    CREATE TABLE [mining].[customer_clusters_summary] (
        cluster_id           INT            NOT NULL PRIMARY KEY,
        cluster_label        NVARCHAR(100)  NOT NULL,
        booking_count        INT            NOT NULL,
        avg_lead_time        DECIMAL(8,2)   NOT NULL,
        avg_total_nights     DECIMAL(8,2)   NOT NULL,
        avg_adr              DECIMAL(10,2)  NOT NULL,
        avg_total_guests     DECIMAL(8,2)   NOT NULL,
        avg_special_requests DECIMAL(8,2)   NOT NULL,
        avg_prev_cancels     DECIMAL(8,2)   NOT NULL,
        cancel_rate_pct      DECIMAL(6,2)   NOT NULL,
        total_actual_revenue DECIMAL(16,2)  NOT NULL,
        total_lost_revenue   DECIMAL(16,2)  NOT NULL
    );

    DROP TABLE IF EXISTS [mining].[association_rules];
    CREATE TABLE [mining].[association_rules] (
        rule_id        INT IDENTITY(1,1) PRIMARY KEY,
        antecedent     NVARCHAR(500) NOT NULL,
        consequent     NVARCHAR(100) NOT NULL,
        support        DECIMAL(6,4)  NOT NULL,
        confidence     DECIMAL(6,4)  NOT NULL,
        lift           DECIMAL(8,4)  NOT NULL
    );
    """)
    conn.commit()

    cur.fast_executemany = True

    cur.executemany(
        "INSERT INTO [mining].[model_evaluation_metrics] (model_name, accuracy, [precision], recall, f1_score, roc_auc, train_rows, test_rows) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        metrics_df[["model_name", "accuracy", "precision", "recall", "f1_score", "roc_auc", "train_rows", "test_rows"]].values.tolist(),
    )

    cur.executemany(
        "INSERT INTO [mining].[feature_importance] (rank_no, feature_name, importance) VALUES (?, ?, ?)",
        fi_df[["rank_no", "feature_name", "importance"]].values.tolist(),
    )

    cur.executemany(
        "INSERT INTO [mining].[booking_cancellation_predictions] (booking_sk, hotel_name, market_segment_name, deposit_type, actual_canceled, predicted_canceled, cancel_probability, risk_tier) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        pred_df[["booking_sk", "hotel_name", "market_segment_name", "deposit_type", "actual_canceled", "predicted_canceled", "cancel_probability", "risk_tier"]].values.tolist(),
    )

    cur.executemany(
        "INSERT INTO [mining].[customer_clusters_summary] (cluster_id, cluster_label, booking_count, avg_lead_time, avg_total_nights, avg_adr, avg_total_guests, avg_special_requests, avg_prev_cancels, cancel_rate_pct, total_actual_revenue, total_lost_revenue) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        clusters_df[[
            "cluster_id", "cluster_label", "booking_count", "avg_lead_time", "avg_total_nights",
            "avg_adr", "avg_total_guests", "avg_special_requests", "avg_prev_cancels",
            "cancel_rate_pct", "total_actual_revenue", "total_lost_revenue"
        ]].values.tolist(),
    )

    cur.executemany(
        "INSERT INTO [mining].[association_rules] (antecedent, consequent, support, confidence, lift) VALUES (?, ?, ?, ?, ?)",
        rules_df[["antecedent_str", "consequent_str", "support", "confidence", "lift"]].values.tolist(),
    )
    conn.commit()
    print("[OK] Persisted all 5 tables into [HotelBooking_DW].[mining].*")


def write_summary_report(
    metrics_df: pd.DataFrame,
    fi_df: pd.DataFrame,
    clusters_df: pd.DataFrame,
    sil_scores: dict,
    rules_df: pd.DataFrame,
    best_model_name: str,
):
    def df_to_md(df: pd.DataFrame) -> str:
        cols = list(df.columns)
        lines = ["| " + " | ".join(cols) + " |", "| " + " | ".join(["---"] * len(cols)) + " |"]
        for _, row in df.iterrows():
            lines.append("| " + " | ".join(str(row[c]) for c in cols) + " |")
        return "\n".join(lines)

    report = f"""# Báo cáo Kết quả Data Mining — Hotel Booking Demand (`mining/`)

Dữ liệu đầu vào được trích xuất trực tiếp từ kho dữ liệu **SQL Server `HotelBooking_DW` (`dw.Fact_Hotel_Booking` JOIN `dw.Dim_*`, `119,389` giao dịch)** và kết quả khai phá được lưu ngược về schema **`[mining]`** trên SQL Server.

---

## 1. Classification — Dự đoán Hủy phòng (`is_canceled`)

* **Tập dữ liệu:** 80% Train (`95,511` dòng) / 20% Test (`23,878` dòng), chia tầng (Stratified) theo `is_canceled`, loại bỏ hoàn toàn các cột rò rỉ dữ liệu (`reservation_status`, `actual_revenue`, `lost_revenue`).
* **Mô hình tốt nhất:** **`{best_model_name}`**

{df_to_md(metrics_df)}

### Top 10 yếu tố quyết định khả năng hủy phòng (Feature Importance)

{df_to_md(fi_df.head(10)[["rank_no", "feature_name", "importance"]])}

* Biểu đồ: `mining/outputs/01_classification_roc_and_cm.png`, `mining/outputs/02_feature_importance.png`
* Bảng SQL kết quả: `[mining].[model_evaluation_metrics]`, `[mining].[feature_importance]`, `[mining].[booking_cancellation_predictions]` (`23,878` bản ghi test kèm xác suất hủy & nhãn `Low / Medium / High Risk`).

---

## 2. Clustering — Phân cụm Khách hàng (`K-Means`, K = 4)

* **Chỉ số Silhouette theo số cụm K:** `{sil_scores}`

{df_to_md(clusters_df[["cluster_id", "cluster_label", "booking_count", "avg_lead_time", "avg_total_nights", "avg_adr", "cancel_rate_pct", "total_actual_revenue", "total_lost_revenue"]])}

* Biểu đồ: `mining/outputs/03_customer_clusters.png`
* Bảng SQL kết quả: `[mining].[customer_clusters_summary]`

---

## 3. Association Rules — Khai phá Luật kết hợp (`Apriori`)

Tìm các tổ hợp thuộc tính có mối liên hệ mạnh (`Lift > 1.15`, `Min Support >= 4%`) dẫn đến kết cục `Outcome:Canceled` hoặc `Outcome:Check-Out`:

{df_to_md(rules_df)}

* Biểu đồ: `mining/outputs/04_association_rules_cancel.png`
* Bảng SQL kết quả: `[mining].[association_rules]`

---

## Cách chạy lại toàn bộ pipeline
```bash
python mining/run_data_mining.py
```
"""
    (ROOT / "README.md").write_text(report, encoding="utf-8", newline="\n")
    print("[OK] Wrote report ->", ROOT / "README.md")


if __name__ == "__main__":
    conn = get_connection()
    try:
        df = load_dw_dataset(conn)
        metrics_df, fi_df, pred_df, best_model_name = run_classification(df)
        clusters_df, sil_scores = run_clustering(df)
        rules_df = run_association_rules(df)
        save_to_sql_server(conn, metrics_df, fi_df, pred_df, clusters_df, rules_df)
        write_summary_report(metrics_df, fi_df, clusters_df, sil_scores, rules_df, best_model_name)
    finally:
        conn.close()
    print("\n=== DATA MINING PIPELINE COMPLETED SUCCESSFULLY ===")

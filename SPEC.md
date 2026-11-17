# Metatronik Sales Dashboard — Plan (SPEC)

Written 17 Nov 2026. Nothing is built yet. This is the plan for you to check.

---

## A. Purpose

Every morning by 8:00 am, the owner can see **yesterday's sales** and **which orders were confirmed or cancelled**, so they know which cancelled orders to follow up today.

The daily order list comes from an **Excel file in Google Drive**. A Manager uploads it into the system each morning.

---

## B. Who can see, add, edit and delete what

| | See orders and totals | Upload the daily Excel file | Edit an order by hand | Delete | Change settings | Change people's roles |
|---|---|---|---|---|---|---|
| **Owner** | Yes | Yes | Yes | Yes | Yes | Yes |
| **Manager** | Yes | Yes | No | No | No | No |
| **Staff** | Yes | No | No | No | No | No |

- New people who sign up start as **Staff**. Only the Owner can make someone a Manager or Owner, or switch someone off.
- A person who has been switched off can't see anything.
- These rules are enforced by the database itself, not only by the screens. So even someone who is good with computers can't get around them.

---

## C. Data tables and columns

**1. orders**: one line per order
- Order ID (for example ORD-10231). Each order ID appears only once.
- Order date (for example 16 Nov 2026)
- Customer name
- Amount (RM, 2 decimals, for example RM 245.50)
- Status: **Confirmed** or **Cancelled**
- Which upload it came from
- When it was added, and who added it

**2. uploads**: one line each time a file is uploaded
- File name
- Date of the orders inside
- Number of orders, number confirmed, number cancelled
- Total sales (RM, confirmed orders only)
- When it was uploaded, and who uploaded it

**Support tables (standard in every system):**
- **profiles**: each person's name, email, role (Owner / Manager / Staff) and whether they're switched on
- **settings**: adjustable numbers and text (see section E)
- **audit_log**: a history of who did what and when: every upload, every status change, every role change. The Owner and Managers can read it.
- **ai_briefs**: saved AI summaries (see section G)

**Your Excel file must have these 5 columns:** Order ID · Order Date · Customer · Amount · Status.
Before we build, we'll check this against one of your real files.

---

## D. Screens per role

**1. Sign in page** (everyone)

**2. Dashboard** (everyone)
- Alerts box at the top (see section I)
- The KPI cards from section F
- A table of the day's orders, with **cancelled orders highlighted in red**
- A date picker to look at any past day
- A search box for an order ID
- A small chart of total sales for the last 14 days
- Works on a phone

**3. Upload page** (Owner and Manager)
- Choose the Excel file and click Upload
- Before saving, the page shows a preview: number of orders, confirmed, cancelled and total RM
- Click **Confirm** to save, or **Cancel** to stop
- If the file has a problem, for example a missing column or an amount that isn't a number, you see a friendly message saying which row is wrong

**4. Settings page** (Owner only)
- Change the numbers and text in section E
- Manage people: change roles, and switch people on or off

**5. History page** (Owner and Manager)
- The audit log: who uploaded what and when, and which orders changed status

---

## E. Rules (with exact numbers)

1. **Cancelled orders are always highlighted in red**, everywhere they appear.
2. **Total sales counts confirmed orders only.** Cancelled orders don't add to sales.
3. **Upload deadline: 8:00 am** (stored in settings, so it can be changed). If yesterday's file hasn't been uploaded by then, the Alerts box shows a warning.
4. **The same order ID uploaded again updates the existing order. No duplicate is created.** If its status changes, for example from Confirmed to Cancelled, the change is recorded in the history.
5. **Wrong files are rejected, not half-saved.** If any row has a problem, nothing from that file is saved.
6. Money is always shown as RM with 2 decimals. Dates are always shown like 17 Nov 2026.

**Stored in settings (the Owner can change these without any rebuilding):**
- Upload deadline time: 08:00
- Owner's WhatsApp number (for the summary button)
- Number of days in the sales chart: 14

---

## F. KPIs (5), each with an action

| # | KPI | What to do with it |
|---|---|---|
| 1 | **Yesterday's total sales (RM)**, confirmed orders only | Compare it with the day before. If it's lower, look at the cancelled list. |
| 2 | **Confirmed orders**: the count, and the list of order IDs | Check these orders are being packed and delivered. |
| 3 | **Cancelled orders**: the count, and the list of order IDs (in red) | Follow up each one today: call the customer and find out why. |
| 4 | **Cancellation rate (%)** = cancelled ÷ all orders | If it keeps going up, look for a common cause (a product, a customer, a delivery problem). |
| 5 | **Today's upload status**: done, or not done by 8:00 am | If it's not done, remind the Manager to upload. |

---

## G. AI feature, and what AI must never do

**AI daily brief (optional button on the Dashboard):**
1. Click **"Make AI brief"**. The system writes a ready-made question from the orders on screen, for example "Summarise yesterday's sales and list the cancelled orders to follow up".
2. Click **Copy**, paste it into Claude, and read the answer.
3. Paste the answer back, tick **"I have checked this"**, then click **Save**. Saved briefs are kept for later.

**AI must never:**
- Have its own key or password stored in the system
- Change, add or delete any order
- Send any message to customers or anyone else
- Be saved without a person ticking "I have checked this"

---

## H. Not today (maybe later)

- **Picking up the file from Google Drive automatically.** Today, the Manager downloads the Excel file from Google Drive and uploads it into the system. Doing this automatically needs extra setup, so it can be a later step.
- Sending WhatsApp messages or emails automatically
- Customer details beyond the name (phone, address)
- Product-level detail (which items were in each order)
- Statuses other than Confirmed and Cancelled
- Real company data. We use **sample data only** until you approve.

---

## I. Notifications (who, when, how)

| Who | When | How |
|---|---|---|
| **Owner** | Every day from 8:00 am | **Alerts box** on the Dashboard: yesterday's total sales, number of confirmed orders and the list of cancelled order IDs |
| **Owner** | Every day from 8:00 am | **"Send to WhatsApp" button**: opens WhatsApp with the summary already typed, and you press send yourself |
| **Owner and Manager** | If there's no upload by 8:00 am | **Red warning** in the Alerts box: "Yesterday's orders have not been uploaded yet" |
| **Staff** | Any time | No alerts. They can only view the Dashboard. |

The system never sends anything to customers.

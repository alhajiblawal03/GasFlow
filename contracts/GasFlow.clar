;; GasFlow - Decentralized Natural Gas Pipeline Capacity Trading and Scheduling System

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-capacity (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-invalid-time (err u106))
(define-constant err-trade-not-active (err u107))

;; Input validation helpers
(define-private (validate-pipeline-id (pipeline-id uint))
  (and (> pipeline-id u0) (< pipeline-id (var-get next-pipeline-id)))
)

(define-private (validate-trade-id (trade-id uint))
  (and (> trade-id u0) (< trade-id (var-get next-trade-id)))
)

(define-private (validate-schedule-id (schedule-id uint))
  (and (> schedule-id u0) (< schedule-id (var-get next-schedule-id)))
)

(define-private (validate-capacity-amount (amount uint))
  (> amount u0)
)

(define-private (validate-time-range (start-time uint) (end-time uint))
  (> end-time start-time)
)

(define-private (validate-string-input (input (string-ascii 50)))
  (> (len input) u0)
)

;; Data Variables
(define-data-var next-pipeline-id uint u1)
(define-data-var next-trade-id uint u1)
(define-data-var next-schedule-id uint u1)

;; Data Maps
(define-map pipelines
  { pipeline-id: uint }
  {
    name: (string-ascii 50),
    owner: principal,
    total-capacity: uint,
    available-capacity: uint,
    price-per-unit: uint,
    active: bool
  }
)

(define-map trades
  { trade-id: uint }
  {
    pipeline-id: uint,
    seller: principal,
    buyer: principal,
    capacity-amount: uint,
    price: uint,
    start-time: uint,
    end-time: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map schedules
  { schedule-id: uint }
  {
    pipeline-id: uint,
    user: principal,
    capacity-reserved: uint,
    start-time: uint,
    end-time: uint,
    active: bool
  }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

;; Pipeline Management Functions

(define-public (register-pipeline (name (string-ascii 50)) (total-capacity uint) (price-per-unit uint))
  (let ((pipeline-id (var-get next-pipeline-id)))
    (asserts! (validate-string-input name) err-invalid-amount)
    (asserts! (validate-capacity-amount total-capacity) err-invalid-amount)
    (asserts! (> price-per-unit u0) err-invalid-amount)
    (map-set pipelines
      { pipeline-id: pipeline-id }
      {
        name: name,
        owner: tx-sender,
        total-capacity: total-capacity,
        available-capacity: total-capacity,
        price-per-unit: price-per-unit,
        active: true
      }
    )
    (var-set next-pipeline-id (+ pipeline-id u1))
    (ok { pipeline-id: pipeline-id })
  )
)

(define-public (update-pipeline-capacity (pipeline-id uint) (new-capacity uint))
  (let ((pipeline (unwrap! (map-get? pipelines { pipeline-id: pipeline-id }) err-not-found)))
    (asserts! (validate-pipeline-id pipeline-id) err-not-found)
    (asserts! (is-eq tx-sender (get owner pipeline)) err-unauthorized)
    (asserts! (validate-capacity-amount new-capacity) err-invalid-amount)
    (map-set pipelines
      { pipeline-id: pipeline-id }
      (merge pipeline { total-capacity: new-capacity, available-capacity: new-capacity })
    )
    (ok { success: true, pipeline-id: pipeline-id })
  )
)

(define-public (toggle-pipeline-status (pipeline-id uint))
  (let ((pipeline (unwrap! (map-get? pipelines { pipeline-id: pipeline-id }) err-not-found)))
    (asserts! (validate-pipeline-id pipeline-id) err-not-found)
    (asserts! (is-eq tx-sender (get owner pipeline)) err-unauthorized)
    (map-set pipelines
      { pipeline-id: pipeline-id }
      (merge pipeline { active: (not (get active pipeline)) })
    )
    (ok { success: true, pipeline-id: pipeline-id })
  )
)

;; Trading Functions

(define-public (create-trade (pipeline-id uint) (capacity-amount uint) (start-time uint) (end-time uint))
  (let (
    (pipeline (unwrap! (map-get? pipelines { pipeline-id: pipeline-id }) err-not-found))
    (trade-id (var-get next-trade-id))
    (total-price (* capacity-amount (get price-per-unit pipeline)))
  )
    (asserts! (validate-pipeline-id pipeline-id) err-not-found)
    (asserts! (get active pipeline) err-trade-not-active)
    (asserts! (validate-capacity-amount capacity-amount) err-invalid-amount)
    (asserts! (>= (get available-capacity pipeline) capacity-amount) err-insufficient-capacity)
    (asserts! (validate-time-range start-time end-time) err-invalid-time)
    (asserts! (is-eq tx-sender (get owner pipeline)) err-unauthorized)

    (map-set trades
      { trade-id: trade-id }
      {
        pipeline-id: pipeline-id,
        seller: tx-sender,
        buyer: tx-sender,
        capacity-amount: capacity-amount,
        price: total-price,
        start-time: start-time,
        end-time: end-time,
        status: "active",
        created-at: block-height
      }
    )

    (map-set pipelines
      { pipeline-id: pipeline-id }
      (merge pipeline { available-capacity: (- (get available-capacity pipeline) capacity-amount) })
    )

    (var-set next-trade-id (+ trade-id u1))
    (ok { trade-id: trade-id, pipeline-id: pipeline-id })
  )
)

(define-public (execute-trade (trade-id uint))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) err-not-found)))
    (asserts! (validate-trade-id trade-id) err-not-found)
    (asserts! (is-eq (get status trade) "active") err-trade-not-active)
    (asserts! (not (is-eq tx-sender (get seller trade))) err-unauthorized)

    (map-set trades
      { trade-id: trade-id }
      (merge trade { buyer: tx-sender, status: "completed" })
    )

    (ok { success: true, trade-id: trade-id })
  )
)

;; Scheduling Functions

(define-public (schedule-capacity (pipeline-id uint) (capacity-amount uint) (start-time uint) (end-time uint))
  (let (
    (pipeline (unwrap! (map-get? pipelines { pipeline-id: pipeline-id }) err-not-found))
    (schedule-id (var-get next-schedule-id))
  )
    (asserts! (validate-pipeline-id pipeline-id) err-not-found)
    (asserts! (get active pipeline) err-trade-not-active)
    (asserts! (validate-capacity-amount capacity-amount) err-invalid-amount)
    (asserts! (>= (get available-capacity pipeline) capacity-amount) err-insufficient-capacity)
    (asserts! (validate-time-range start-time end-time) err-invalid-time)

    (map-set schedules
      { schedule-id: schedule-id }
      {
        pipeline-id: pipeline-id,
        user: tx-sender,
        capacity-reserved: capacity-amount,
        start-time: start-time,
        end-time: end-time,
        active: true
      }
    )

    (map-set pipelines
      { pipeline-id: pipeline-id }
      (merge pipeline { available-capacity: (- (get available-capacity pipeline) capacity-amount) })
    )

    (var-set next-schedule-id (+ schedule-id u1))
    (ok { schedule-id: schedule-id, pipeline-id: pipeline-id })
  )
)

(define-public (cancel-schedule (schedule-id uint))
  (let (
    (schedule (unwrap! (map-get? schedules { schedule-id: schedule-id }) err-not-found))
    (pipeline (unwrap! (map-get? pipelines { pipeline-id: (get pipeline-id schedule) }) err-not-found))
  )
    (asserts! (validate-schedule-id schedule-id) err-not-found)
    (asserts! (is-eq tx-sender (get user schedule)) err-unauthorized)
    (asserts! (get active schedule) err-trade-not-active)

    (map-set schedules
      { schedule-id: schedule-id }
      (merge schedule { active: false })
    )

    (map-set pipelines
      { pipeline-id: (get pipeline-id schedule) }
      (merge pipeline { available-capacity: (+ (get available-capacity pipeline) (get capacity-reserved schedule)) })
    )

    (ok { success: true, schedule-id: schedule-id })
  )
)

;; Read-only Functions

(define-read-only (get-pipeline (pipeline-id uint))
  (map-get? pipelines { pipeline-id: pipeline-id })
)

(define-read-only (get-trade (trade-id uint))
  (map-get? trades { trade-id: trade-id })
)

(define-read-only (get-schedule (schedule-id uint))
  (map-get? schedules { schedule-id: schedule-id })
)

(define-read-only (get-user-balance (user principal))
  (default-to { balance: u0 } (map-get? user-balances { user: user }))
)

(define-read-only (get-pipeline-count)
  (- (var-get next-pipeline-id) u1)
)

(define-read-only (get-trade-count)
  (- (var-get next-trade-id) u1)
)

(define-read-only (get-schedule-count)
  (- (var-get next-schedule-id) u1)
)

;; Credit Monitoring Service Platform Contract
;; Smart contract system that enables comprehensive credit tracking and monitoring

;; Define constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_USER_NOT_FOUND (err u101))
(define-constant ERR_USER_EXISTS (err u102))
(define-constant ERR_INVALID_SCORE (err u103))
(define-constant ERR_ALERT_NOT_FOUND (err u104))
(define-constant ERR_DISPUTE_NOT_FOUND (err u105))

;; Data variables
(define-data-var next-alert-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var total-users uint u0)

;; Data maps
(define-map credit-profiles
  { user: principal }
  {
    current-score: uint,
    previous-score: uint,
    score-change: int,
    last-updated: uint,
    monitoring-status: (string-ascii 20),
    enrollment-date: uint
  }
)

(define-map credit-alerts
  { alert-id: uint }
  {
    user: principal,
    alert-type: (string-ascii 30),
    message: (string-ascii 200),
    severity: (string-ascii 10),
    timestamp: uint,
    is-read: bool
  }
)

(define-map identity-monitoring
  { user: principal }
  {
    identity-verified: bool,
    suspicious-activity-count: uint,
    last-verification: uint,
    monitoring-level: (string-ascii 15)
  }
)

(define-map dispute-records
  { dispute-id: uint }
  {
    user: principal,
    dispute-type: (string-ascii 50),
    description: (string-ascii 300),
    status: (string-ascii 15),
    filed-date: uint,
    resolution-date: uint
  }
)

(define-map score-history
  { user: principal, timestamp: uint }
  {
    score: uint,
    factors: (string-ascii 100),
    change-reason: (string-ascii 100)
  }
)

;; Public functions
(define-public (enroll-user)
  (begin
    (asserts! (is-none (map-get? credit-profiles { user: tx-sender })) ERR_USER_EXISTS)
    
    (map-set credit-profiles
      { user: tx-sender }
      {
        current-score: u0,
        previous-score: u0,
        score-change: 0,
        last-updated: stacks-block-height,
        monitoring-status: "active",
        enrollment-date: stacks-block-height
      }
    )
    
    (map-set identity-monitoring
      { user: tx-sender }
      {
        identity-verified: false,
        suspicious-activity-count: u0,
        last-verification: u0,
        monitoring-level: "basic"
      }
    )
    
    (var-set total-users (+ (var-get total-users) u1))
    (ok true)
  )
)

(define-public (update-credit-score (user principal) (new-score uint) (factors (string-ascii 100)) (reason (string-ascii 100)))
  (let
    (
      (profile (unwrap! (map-get? credit-profiles { user: user }) ERR_USER_NOT_FOUND))
      (current-score (get current-score profile))
      (score-change (- (to-int new-score) (to-int current-score)))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-score u850) ERR_INVALID_SCORE)
    
    ;; Update credit profile
    (map-set credit-profiles
      { user: user }
      (merge profile
        {
          current-score: new-score,
          previous-score: current-score,
          score-change: score-change,
          last-updated: stacks-block-height
        }
      )
    )
    
    ;; Store score history
    (map-set score-history
      { user: user, timestamp: stacks-block-height }
      {
        score: new-score,
        factors: factors,
        change-reason: reason
      }
    )
    
    ;; Create alert if significant change
    (and (or (>= score-change 30) (<= score-change -30))
         (is-ok (create-credit-alert user "score-change" "Significant credit score change detected" "high")))
    
    (ok true)
  )
)

(define-public (create-credit-alert (user principal) (alert-type (string-ascii 30)) (message (string-ascii 200)) (severity (string-ascii 10)))
  (let
    (
      (alert-id (var-get next-alert-id))
    )
    (asserts! (is-some (map-get? credit-profiles { user: user })) ERR_USER_NOT_FOUND)
    
    (map-set credit-alerts
      { alert-id: alert-id }
      {
        user: user,
        alert-type: alert-type,
        message: message,
        severity: severity,
        timestamp: stacks-block-height,
        is-read: false
      }
    )
    
    (var-set next-alert-id (+ alert-id u1))
    (ok alert-id)
  )
)

(define-public (mark-alert-read (alert-id uint))
  (let
    (
      (alert (unwrap! (map-get? credit-alerts { alert-id: alert-id }) ERR_ALERT_NOT_FOUND))
    )
    (asserts! (is-eq (get user alert) tx-sender) ERR_UNAUTHORIZED)
    
    (map-set credit-alerts
      { alert-id: alert-id }
      (merge alert { is-read: true })
    )
    
    (ok true)
  )
)

(define-public (verify-identity (user principal))
  (let
    (
      (identity-info (unwrap! (map-get? identity-monitoring { user: user }) ERR_USER_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set identity-monitoring
      { user: user }
      (merge identity-info
        {
          identity-verified: true,
          last-verification: stacks-block-height
        }
      )
    )
    
    (ok true)
  )
)

(define-public (report-suspicious-activity (user principal))
  (let
    (
      (identity-info (unwrap! (map-get? identity-monitoring { user: user }) ERR_USER_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set identity-monitoring
      { user: user }
      (merge identity-info
        {
          suspicious-activity-count: (+ (get suspicious-activity-count identity-info) u1)
        }
      )
    )
    
    (try! (create-credit-alert user "identity-alert" "Suspicious activity detected on your account" "critical"))
    (ok true)
  )
)

(define-public (file-dispute (dispute-type (string-ascii 50)) (description (string-ascii 300)))
  (let
    (
      (dispute-id (var-get next-dispute-id))
    )
    (asserts! (is-some (map-get? credit-profiles { user: tx-sender })) ERR_USER_NOT_FOUND)
    
    (map-set dispute-records
      { dispute-id: dispute-id }
      {
        user: tx-sender,
        dispute-type: dispute-type,
        description: description,
        status: "pending",
        filed-date: stacks-block-height,
        resolution-date: u0
      }
    )
    
    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)
  )
)

(define-public (resolve-dispute (dispute-id uint) (resolution (string-ascii 15)))
  (let
    (
      (dispute (unwrap! (map-get? dispute-records { dispute-id: dispute-id }) ERR_DISPUTE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status dispute) "pending") ERR_UNAUTHORIZED)
    
    (map-set dispute-records
      { dispute-id: dispute-id }
      (merge dispute
        {
          status: resolution,
          resolution-date: stacks-block-height
        }
      )
    )
    
    (ok true)
  )
)

(define-public (upgrade-monitoring-level (monitoring-level (string-ascii 15)))
  (let
    (
      (identity-info (unwrap! (map-get? identity-monitoring { user: tx-sender }) ERR_USER_NOT_FOUND))
    )
    (map-set identity-monitoring
      { user: tx-sender }
      (merge identity-info { monitoring-level: monitoring-level })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-credit-profile (user principal))
  (map-get? credit-profiles { user: user })
)

(define-read-only (get-alert (alert-id uint))
  (map-get? credit-alerts { alert-id: alert-id })
)

(define-read-only (get-identity-monitoring (user principal))
  (map-get? identity-monitoring { user: user })
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? dispute-records { dispute-id: dispute-id })
)

(define-read-only (get-score-history (user principal) (timestamp uint))
  (map-get? score-history { user: user, timestamp: timestamp })
)

(define-read-only (get-total-users)
  (var-get total-users)
)

(define-read-only (get-next-alert-id)
  (var-get next-alert-id)
)

(define-read-only (get-next-dispute-id)
  (var-get next-dispute-id)
)


;; title: credit-tracker
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;


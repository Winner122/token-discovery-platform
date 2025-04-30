;; Token Trove - Stacks Blockchain Project Discovery Platform
;; This contract manages the listing, curation, and discovery of upcoming token and NFT projects
;; on the Stacks blockchain. It enables project creators to list their projects and allows the
;; community to curate content through upvoting.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROJECT-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-UPVOTED (err u102))
(define-constant ERR-INVALID-PROJECT-ID (err u103))
(define-constant ERR-INVALID-DATA (err u104))
(define-constant ERR-ALREADY-EXISTS (err u105))
(define-constant ERR-NOT-MODERATOR (err u106))
(define-constant ERR-BANNED (err u107))
(define-constant ERR-PROJECT-INACTIVE (err u108))

;; Data Variables
(define-data-var next-project-id uint u1)
(define-data-var admin principal tx-sender)
(define-data-var platform-active bool true)

;; Project Types and Categories
(define-constant PROJECT-TYPE-TOKEN u1)
(define-constant PROJECT-TYPE-NFT u2)

(define-constant PROJECT-STAGE-PRE-LAUNCH u1)
(define-constant PROJECT-STAGE-EARLY-ACCESS u2)
(define-constant PROJECT-STAGE-PUBLIC u3)

;; Data Maps
(define-map projects
  { project-id: uint }
  {
    creator: principal,
    name: (string-ascii 100),
    description: (string-utf8 500),
    project-type: uint,
    category: (string-ascii 50),
    stage: uint,
    creation-time: uint,
    website-url: (optional (string-ascii 100)),
    social-links: (list 5 (string-ascii 100)),
    contract-address: (optional principal),
    upvote-count: uint,
    active: bool
  }
)

;; Map to track upvotes to prevent duplicate voting
(define-map upvotes
  { project-id: uint, user: principal }
  { voted: bool }
)

;; Map for project tags to enhance discoverability
(define-map project-tags
  { project-id: uint, tag: (string-ascii 20) }
  { exists: bool }
)

;; Moderator access control
(define-map moderators
  { moderator: principal }
  { active: bool }
)

;; Banned users for platform safety
(define-map banned-users
  { user: principal }
  { banned: bool }
)

;; Metadata about total projects and platform metrics
(define-map platform-stats
  { stat-name: (string-ascii 50) }
  { value: uint }
)

;; Private Functions

;; Check if caller is an admin
(define-private (is-admin)
  (is-eq tx-sender (var-get admin))
)

;; Check if caller is a moderator
(define-private (is-moderator)
  (default-to false (get active (map-get? moderators { moderator: tx-sender })))
)

;; Check if user is banned
(define-private (is-banned (user principal))
  (default-to false (get banned (map-get? banned-users { user: user })))
)

;; Check if project exists
(define-private (project-exists (project-id uint))
  (is-some (map-get? projects { project-id: project-id }))
)

;; Increment project counter and get new ID
(define-private (get-next-project-id)
  (let ((current-id (var-get next-project-id)))
    (var-set next-project-id (+ current-id u1))
    current-id
  )
)

;; Update platform stats
(define-private (increment-stat (stat-name (string-ascii 50)))
  (let ((current-value (default-to u0 (get value (map-get? platform-stats { stat-name: stat-name })))))
    (map-set platform-stats
      { stat-name: stat-name }
      { value: (+ current-value u1) }
    )
  )
)

;; Check if a project is active
(define-private (is-project-active (project-id uint))
  (default-to 
    false 
    (get active (map-get? projects { project-id: project-id }))
  )
)

;; Calculate time-decay factor for voting
(define-private (calculate-vote-weight (creation-time uint))
  (let (
    (current-time block-height)
    (time-diff (- current-time creation-time))
  )
    ;; Simple decay calculation - newer projects get a slightly higher vote weight
    (if (< time-diff u10000)
        u1
        u1) ;; No decay for now, can implement a more complex decay function if needed
  )
)

;; Read-Only Functions

;; Get project details
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

;; Get user's vote status for a project
(define-read-only (get-user-vote (project-id uint) (user principal))
  (default-to 
    { voted: false } 
    (map-get? upvotes { project-id: project-id, user: user })
  )
)

;; Check if user is moderator
(define-read-only (check-moderator (user principal))
  (default-to 
    { active: false } 
    (map-get? moderators { moderator: user })
  )
)

;; Get platform statistics
(define-read-only (get-platform-stat (stat-name (string-ascii 50)))
  (default-to 
    { value: u0 } 
    (map-get? platform-stats { stat-name: stat-name })
  )
)

;; Get a project's tags
(define-read-only (has-project-tag (project-id uint) (tag (string-ascii 20)))
  (default-to 
    { exists: false } 
    (map-get? project-tags { project-id: project-id, tag: tag })
  )
)

;; Public Functions

;; Submit a new project
(define-public (submit-project 
    (name (string-ascii 100))
    (description (string-utf8 500))
    (project-type uint)
    (category (string-ascii 50))
    (stage uint)
    (website-url (optional (string-ascii 100)))
    (social-links (list 5 (string-ascii 100)))
    (contract-address (optional principal))
  )
  (let (
    (caller tx-sender)
    (project-id (get-next-project-id))
  )
    ;; Validate inputs and user status
    (asserts! (var-get platform-active) (err u109)) ;; Check if platform is active
    (asserts! (not (is-banned caller)) ERR-BANNED)
    (asserts! (or (is-eq project-type PROJECT-TYPE-TOKEN) (is-eq project-type PROJECT-TYPE-NFT)) ERR-INVALID-DATA)
    (asserts! (or (is-eq stage PROJECT-STAGE-PRE-LAUNCH) 
                 (is-eq stage PROJECT-STAGE-EARLY-ACCESS) 
                 (is-eq stage PROJECT-STAGE-PUBLIC)) ERR-INVALID-DATA)
    
    ;; Create new project record
    (map-set projects
      { project-id: project-id }
      {
        creator: caller,
        name: name,
        description: description,
        project-type: project-type,
        category: category,
        stage: stage,
        creation-time: block-height,
        website-url: website-url,
        social-links: social-links,
        contract-address: contract-address,
        upvote-count: u0,
        active: true
      }
    )
    
    ;; Update platform stats
    (increment-stat "total-projects")
    (ok project-id)
  )
)

;; Update an existing project (only creator can update)
(define-public (update-project
    (project-id uint)
    (name (string-ascii 100))
    (description (string-utf8 500))
    (category (string-ascii 50))
    (stage uint)
    (website-url (optional (string-ascii 100)))
    (social-links (list 5 (string-ascii 100)))
    (contract-address (optional principal))
  )
  (let (
    (project-data (map-get? projects { project-id: project-id }))
  )
    ;; Validate project exists and caller is authorized
    (asserts! (is-some project-data) ERR-PROJECT-NOT-FOUND)
    (asserts! (is-eq (get creator (unwrap-panic project-data)) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-banned tx-sender)) ERR-BANNED)
    
    ;; Update project data
    (map-set projects
      { project-id: project-id }
      (merge (unwrap-panic project-data)
        {
          name: name,
          description: description,
          category: category,
          stage: stage,
          website-url: website-url,
          social-links: social-links,
          contract-address: contract-address
        }
      )
    )
    (ok true)
  )
)

;; Upvote a project
(define-public (upvote-project (project-id uint))
  (let (
    (caller tx-sender)
    (project-data (map-get? projects { project-id: project-id }))
    (user-vote (map-get? upvotes { project-id: project-id, user: caller }))
  )
    ;; Validate upvote eligibility
    (asserts! (is-some project-data) ERR-PROJECT-NOT-FOUND)
    (asserts! (is-project-active project-id) ERR-PROJECT-INACTIVE)
    (asserts! (not (is-banned caller)) ERR-BANNED)
    (asserts! (is-none user-vote) ERR-ALREADY-UPVOTED)
    
    ;; Record user vote
    (map-set upvotes
      { project-id: project-id, user: caller }
      { voted: true }
    )
    
    ;; Update project upvote count
    (let (
      (current-votes (get upvote-count (unwrap-panic project-data)))
      (vote-weight (calculate-vote-weight (get creation-time (unwrap-panic project-data))))
      (new-vote-count (+ current-votes vote-weight))
    )
      (map-set projects
        { project-id: project-id }
        (merge (unwrap-panic project-data)
          { upvote-count: new-vote-count }
        )
      )
      (ok true)
    )
  )
)

;; Add a tag to a project
(define-public (add-project-tag (project-id uint) (tag (string-ascii 20)))
  (let (
    (project-data (map-get? projects { project-id: project-id }))
  )
    ;; Validate project and authorization
    (asserts! (is-some project-data) ERR-PROJECT-NOT-FOUND)
    (asserts! (or 
               (is-eq (get creator (unwrap-panic project-data)) tx-sender)
               (is-moderator)
              ) ERR-NOT-AUTHORIZED)
    
    ;; Set the tag
    (map-set project-tags
      { project-id: project-id, tag: tag }
      { exists: true }
    )
    (ok true)
  )
)

;; Remove a tag from a project
(define-public (remove-project-tag (project-id uint) (tag (string-ascii 20)))
  (let (
    (project-data (map-get? projects { project-id: project-id }))
  )
    ;; Validate project and authorization
    (asserts! (is-some project-data) ERR-PROJECT-NOT-FOUND)
    (asserts! (or 
               (is-eq (get creator (unwrap-panic project-data)) tx-sender)
               (is-moderator)
              ) ERR-NOT-AUTHORIZED)
    
    ;; Remove the tag
    (map-delete project-tags { project-id: project-id, tag: tag })
    (ok true)
  )
)

;; Moderator Functions

;; Add a moderator (admin only)
(define-public (add-moderator (moderator principal))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (map-set moderators
      { moderator: moderator }
      { active: true }
    )
    (ok true)
  )
)

;; Remove a moderator (admin only)
(define-public (remove-moderator (moderator principal))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (map-delete moderators { moderator: moderator })
    (ok true)
  )
)

;; Ban a user (moderator or admin)
(define-public (ban-user (user principal))
  (begin
    (asserts! (or (is-admin) (is-moderator)) ERR-NOT-AUTHORIZED)
    (map-set banned-users
      { user: user }
      { banned: true }
    )
    (ok true)
  )
)

;; Unban a user (moderator or admin)
(define-public (unban-user (user principal))
  (begin
    (asserts! (or (is-admin) (is-moderator)) ERR-NOT-AUTHORIZED)
    (map-delete banned-users { user: user })
    (ok true)
  )
)

;; Moderate a project (deactivate it)
(define-public (moderate-project (project-id uint) (active bool))
  (let (
    (project-data (map-get? projects { project-id: project-id }))
  )
    (asserts! (or (is-admin) (is-moderator)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some project-data) ERR-PROJECT-NOT-FOUND)
    
    (map-set projects
      { project-id: project-id }
      (merge (unwrap-panic project-data)
        { active: active }
      )
    )
    (ok true)
  )
)

;; Admin Functions

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (var-set admin new-admin)
    (ok true)
  )
)

;; Set platform active status
(define-public (set-platform-active (active bool))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (var-set platform-active active)
    (ok true)
  )
)
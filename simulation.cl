;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2015
;;; Last Modified <michael 2017-12-28 19:03:21>

;; -- marks
;; -- atan/acos may return #C() => see CLTL
;; -- use CIS ?

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Todo: User settings
;;; Wind & Boat
;;; - sail change penalty 
;;; - tack/gybe penalty 
;;; Search parameters
;;; - land check [on]|off
;;; - long-step-threshold 12h|24h (?)
;;; - long-step-value 30min|[60min]
;;; Display
;;; - display isochrones [on]|off
;;; - display tracks on|[off]


(in-package :virtualhelm)

;;; time in seconds
(defconstant +10min+ (* 10 60))
(defconstant +20min+ (* 20 60))
(defconstant +30min+ (* 30 60))
(defconstant +60min+ (* 60 60))
(defconstant +3h+ (* 3 60 60))
(defconstant +6h+ (* 6 60 60))
(defconstant +12h+ (* 12 60 60))
(defconstant +24h+ (* 24 60 60))
(defconstant +48h+ (* 48 60 60))

(defvar *isochrones* nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; A routing stores the start and destination of the route
;;; and other routing parameters.
        
(defstruct routing
  (forecast-bundle 'noaa-bundle)
  (polars "vo65")
  (starttime nil) ;; NIL or "yyyy-MM-ddThh:mm" (datetime-local format)
  (starttimezone "+01:00") ;; NIL or "yyyy-MM-ddThh:mm" (datetime-local format)
  (options ())
  (minwind t) ;; m/s !!
  (start +lessables+)
  (dest +lacoruna+)
  (mode +max-origin+)
  (fan 90)
  (angle-increment 3)
  (max-points-per-isochrone 300)
  (stepmax +24h+))

(defun routing-foils (routing)
  (member "foil" (routing-options routing) :test #'string=))
(defun routing-hull (routing)
  (member "hull" (routing-options routing) :test #'string=))
(defun routing-winches (routing)
  (member "winch" (routing-options routing) :test #'string=))

(defstruct routeinfo best stats tracks isochrones)
(defstruct routestats sails min-wind max-wind min-twa max-twa)
  
(defstruct isochrone center time offset path)

(defstruct twainfo twa heading path)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Isochrones are described by sets of routepoints.
;;;
;;; ### Think of a good sorting/data structure to support finding the most advanced point in a sector

(defstruct routepoint
  position
  time
  heading
  twa
  speed
  penalty
  sail
  wind-dir
  wind-speed
  predecessor
  origin-angle
  origin-distance
  sort-angle%
  destination-angle
  destination-distance)

(defmethod print-object ((thing routepoint) stream)
  (format stream " ~a@~a"
          (routepoint-position thing)
          (routepoint-time thing)))
                          
(defun get-route (routing)
  (let ((start-pos (routing-start routing))
        (dest-pos (routing-dest routing)))
    (if (>= (- (latlng-lng dest-pos) (latlng-lng start-pos)) 180)
        (setf dest-pos
              (make-latlng :lat (latlng-lat dest-pos)
                           :lng (- (latlng-lng dest-pos) 360))))

    (let*
        ((forecast-bundle (or (get-forecast-bundle (routing-forecast-bundle routing))
                              (get-forecast-bundle 'constant-wind-bundle)))
         (polars-name (routing-polars routing))
         (sails (encode-options (routing-options routing)))
         (angle-increment (routing-angle-increment routing))
         (max-points (routing-max-points-per-isochrone routing))
         (dest-heading (round (course-angle start-pos dest-pos)))
         (start-time
          ;; Start time NIL is parsed as NOW
          (parse-datetime-local (routing-starttime routing)
                                :timezone (routing-starttimezone routing))) 
         (isochrones nil))
    
      (log2:info "Routing from ~a to ~a / course angle ~a searching +/-~a"
                 start-pos
                 dest-pos
                 dest-heading
                 (routing-fan routing))

      (do* ( ;; Iteration stops when destination was reached
            (reached nil)
            (error nil)
            ;; Iteration stops when stepmax seconds have elapsed
            (stepnum 0
                     (1+ stepnum))
            (stepsum 0
                     (+ stepsum step-size))
            (step-size (step-size start-time)
                       (step-size start-time step-time))
            (pointnum 0)
            (start-offset (/ (timestamp-difference start-time (fcb-time forecast-bundle)) 3600))
            (elapsed0 (now))
            ;; The initial isochrone is just the start point, heading towards destination
            (isochrone (list (make-routepoint :position start-pos
                                              :time (format-datetime nil start-time)
                                              :heading  dest-heading
                                              :origin-distance 0
                                              :destination-distance (course-distance start-pos dest-pos)))
                       next-isochrone)
            ;; The next isochrone - in addition we collect all hourly isochrones
            (next-isochrone (make-array 0 :adjustable t :fill-pointer 0)
                            (make-array 0 :adjustable t :fill-pointer 0))
            (index 0 0)
            ;; Get min and max heading of the point of each isochrone for sorting
            (min-heading 360 360)
            (max-heading 0 0)
            ;; Advance the simulation time AFTER each iteration - this is most likely what GE does
            (step-time (adjust-timestamp start-time (:offset :sec step-size))
                       (adjust-timestamp step-time (:offset :sec step-size)))
            (step-time-string (format-datetime nil step-time)
                              (format-datetime nil step-time))
            ;; Get wind data for simulation time
            (forecast (get-forecast forecast-bundle step-time)
                      (get-forecast forecast-bundle step-time)))
        
           ;; When the maximum number of iterations is reached, construct the best path
           ;; from the most advanced point's predecessor chain.
           ((or reached
                error
                (>= stepsum (routing-stepmax routing)))
            (let* ((elapsed (timestamp-difference (now) elapsed0)))
              (log2:info "Elapsed ~2$, Positions ~a, Isochrones ~a | p/s=~2$ | s/i=~4$ | tpi=~2$ |"
                         elapsed
                         pointnum
                         stepnum
                         (/ pointnum elapsed)
                         (/ elapsed stepnum)
                         (coerce (/ pointnum stepnum) 'float)))
            (let ((best-route (construct-route (extract-points isochrone))))
              (setf *isochrones*  isochrones)
              (make-routeinfo :best best-route
                              :stats (get-statistics best-route)
                              :tracks (extract-tracks isochrone)
                              :isochrones (loop
                                             :for i :in isochrones
                                             :collect (make-isochrone :time (isochrone-time i)
                                                                      :offset (isochrone-offset i)
                                                                      :path (loop
                                                                               :for r :across (isochrone-path i)
                                                                               :collect (routepoint-position r)))))))
        (log2:info "Isochrone ~a at ~a, ~a points" stepnum step-time-string (length isochrone))
        ;; Iterate over each point in the current isochrone
        (map nil
             (lambda (routepoint)
               (when routepoint 
                 (let* ((dest-angle (normalize-angle
                                     (round
                                      (course-angle (routepoint-position routepoint) dest-pos))))
                        (left (normalize-heading (- dest-heading (routing-fan routing))))
                        (right (normalize-heading (+ dest-heading (routing-fan routing)))))
                   ;; Keep track of min and max heading of point in isochrone
                   (when (< left min-heading)
                     (setf min-heading left))
                   (when (> right max-heading)
                     (setf max-heading right))
                   (when (> left right)
                     (incf right 360))
                   (loop
                      :for heading-index :from left :to right :by angle-increment
                      :for heading = (normalize-heading heading-index)
                      :do (multiple-value-bind (twa sail speed reason wind-dir wind-speed)
                              (get-penalized-avg-speed routing routepoint forecast polars-name sails heading)
                            (when (or (<= -165 twa -40)
                                      (<= 40 twa 165))
                              (let*
                                  ((new-pos (add-distance-exact (routepoint-position routepoint)
                                                                (* speed step-size)
                                                                (coerce heading 'double-float))))
                                (incf pointnum)
                                (vector-push-extend
                                 (make-routepoint :position new-pos
                                                  :time step-time-string
                                                  :heading heading
                                                  :twa (round twa)
                                                  :speed speed
                                                  :penalty reason
                                                  :sail sail
                                                  :wind-dir wind-dir
                                                  :wind-speed wind-speed
                                                  :predecessor routepoint
                                                  :origin-angle (course-angle start-pos new-pos)
                                                  :origin-distance (course-distance new-pos start-pos)
                                                  :destination-angle "not computed"
                                                  :destination-distance nil)
                                 next-isochrone)
                                (incf index))))))))
             isochrone)
        (let ((candidate (filter-isochrone next-isochrone max-points :criterion (routing-mode routing))))
          (cond
            (candidate
             (loop
                :for p :across candidate
                :when p
                :do (progn
                      (setf (routepoint-destination-distance p)
                            (course-distance (routepoint-position p) dest-pos))
                      (when (< (routepoint-destination-distance p) 10000)
                        (setf reached t))))
             (setf next-isochrone candidate))
            (t
             (setf error t)))
          (when reached
            (log2:info "Reached destination at ~a" step-time)))
        ;; Collect hourly isochrones
        (multiple-value-bind (q r) (truncate (timestamp-to-universal step-time) 3600)
          (declare (ignore q))
          (when (zerop r)
            (let ((iso (make-isochrone :center start-pos
                                       :time (to-rfc3339-timestring step-time)
                                       :offset (truncate (+ start-offset (/ stepsum 3600)) 1.0)
                                       :path (extract-points next-isochrone))))
              (push iso isochrones))))))))

(defun extract-points (isochrone)
  (let ((points (loop :for p :across isochrone :when p :collect p)))
    (make-array (length points) :initial-contents points)))

(defun step-size (start-time &optional (step-time nil))
  (cond
    ((null step-time)
     ;; First step - runs up to full 10min 
     (let* ((time (timestamp-to-unix start-time)))
       (- (* 600 (truncate (+ time 600) 600))
          time)))
    (t
     (let ((delta-t (timestamp-difference step-time (timestamp-maximize-part start-time :hour))))
       (cond ((<= delta-t (* 36 600))
              600)
             ((<= delta-t (* 72 600))
              1200)
             ((<= delta-t (* 144 600))
              1800)
             (t
              3600))))))

(defvar +foil-speeds+ (map 'vector #'knots-to-m/s
                           #(0.0 11.0 16.0 35.0 40.0 70.0)) )
(defvar +foil-angles+ #(0.0 70.0 80.0 160.0 170.0 180.0))
(defvar +foil-matrix+ #2a((1.00 1.00 1.00 1.00 1.00 1.00)
                          (1.00 1.00 1.00 1.00 1.00 1.00)
                          (1.00 1.00 1.04 1.04 1.00 1.00)
                          (1.00 1.00 1.04 1.04 1.00 1.00)
                          (1.00 1.00 1.00 1.00 1.00 1.00)
                          (1.00 1.00 1.00 1.00 1.00 1.00)))
(defun foiling-factor (speed twa)
  (multiple-value-bind
        (speed-index speed-fraction)
      (fraction-index speed +foil-speeds+)
    (multiple-value-bind
          (angle-index angle-fraction)
        (fraction-index (abs twa) +foil-angles+)
      (bilinear-unit speed-fraction
                     angle-fraction
                     (aref +foil-matrix+ speed-index angle-index)
                     (aref +foil-matrix+ (1+ speed-index) angle-index)
                     (aref +foil-matrix+ speed-index (1+ angle-index))
                     (aref +foil-matrix+ (1+ speed-index) (1+ angle-index))))))
         
(defun get-penalized-avg-speed (routing predecessor forecast polars-name sails heading)
  (multiple-value-bind (speed twa sail wind-dir wind-speed)
      (heading-boatspeed forecast polars-name sails (routepoint-position predecessor) heading)
    (when (routing-minwind routing)
      (setf speed (max 2.0578d0 speed)))
    (when
        ;; Foiling speed if twa and tws (in m/s) falls in the specified range
        (routing-foils routing)
      (setf speed (* speed (foiling-factor speed twa))))
    (when (routing-hull routing)
      (setf speed (* speed 1.003)))
    (let ((pspeed
           (if (routing-winches routing)
               (* speed 0.9375)
               (* speed 0.75))))
      (cond
        ((and
          (not (equal sail (routepoint-sail predecessor)))
          (not (equal twa (routepoint-twa predecessor))))
         (values twa sail pspeed "Sail Change" wind-dir wind-speed))
        ((or (< twa 0 (routepoint-twa predecessor))
             (< (routepoint-twa predecessor) 0 twa))
         (values twa sail pspeed "Tack/Gybe" wind-dir wind-speed))
        (t
         (values twa sail speed nil wind-dir wind-speed))))))

(defun southbound-p (min-heading max-heading)
  (< min-heading 180 max-heading))
           
(defun construct-route (isochrone)
  (let ((min-dtf nil)
        (min-point nil)
        (route nil))
    (loop
       :for point :across isochrone
       :do (when (or (null min-point)
                     (< (routepoint-destination-distance point) min-dtf))
             (setf min-dtf (routepoint-destination-distance point)
                   min-point point)))
    (do ((cur-point min-point (routepoint-predecessor cur-point))
         (predecessor nil cur-point))
        ((null cur-point)
         route)
      (when (or (null predecessor)
                (not (eql (routepoint-heading cur-point) (routepoint-heading predecessor)))
                (not (eql (routepoint-sail cur-point) (routepoint-sail predecessor))))
        (let ((next-point (copy-routepoint cur-point)))
          (setf (routepoint-predecessor next-point) nil)
          (push next-point route))))))

(defun get-statistics (track)
  (let ((sails nil)
        (min-wind 100)
        (max-wind 0)
        (min-twa 180)
        (max-twa 0))
    (dolist (point track)
      (when (routepoint-sail point)
        (pushnew (routepoint-sail point) sails))
      (setf min-wind
            (min (m/s-to-knots
                  (or (routepoint-wind-speed point) 100))
                 min-wind))
      (setf max-wind
            (max (m/s-to-knots
                  (or (routepoint-wind-speed point) 0)) max-wind))
      (setf min-twa
            (min (abs (or (routepoint-twa point) 180)) min-twa))
      (setf max-twa
            (max (abs (or (routepoint-twa point) 0)) max-twa)))
    (make-routestats :sails sails
                     :min-wind min-wind
                     :max-wind max-wind
                     :min-twa min-twa
                     :max-twa max-twa)))

(defun extract-tracks (isochrone)
  (loop
     :for point :across isochrone
     :for k :from 0
     :collect (do ((p point (routepoint-predecessor p))
                   (v (list)))
                  ((null p)
                   v)
                (push (routepoint-position p) v))))

(defun get-twa-path (routing
                     &key
                       time
                       lat-a
                       lng-a
                       lat
                       lng
                       (total-time +12h+)
                       (step-num (truncate total-time +10min+)))
  (let* ((forecast-bundle (or (get-forecast-bundle (routing-forecast-bundle routing))
                              (get-forecast-bundle 'constant-wind-bundle)))
         (polars-name (routing-polars routing))
         (sails (encode-options (routing-options routing)))
         (start-time (or time (now)))
         (step-time +10min+)
         (startpos (make-latlng :lat lat-a :lng lng-a)))
    (let* ((heading (course-angle startpos (make-latlng :lat lat :lng lng)))
           (curpos (copy-latlng startpos))
           (wind-dir (get-wind-forecast (get-forecast forecast-bundle start-time) startpos))
           (twa (coerce (round (heading-twa wind-dir heading)) 'double-float))
           (path nil))
      (dotimes (k
                 step-num
                (make-twainfo :twa twa
                              :heading (normalize-heading
                                        (round heading))
                              :path (reverse (push (copy-latlng curpos) path))))
        ;; Save current position
        (push (copy-latlng curpos) path)
        (adjust-timestamp! start-time (:offset :sec step-time))
        (let ((forecast (get-forecast forecast-bundle start-time)))
          (multiple-value-bind (speed heading)
              (twa-boatspeed forecast polars-name sails curpos twa)
            (setf curpos (add-distance-exact curpos (* speed step-time) heading))))))))

(defun twa-heading (wind-dir angle)
  "Compute HEADING resulting from TWA in WIND"
  (normalize-heading (- wind-dir angle)))

(defvar *boat-speed-ht* (make-hash-table :test #'equal))

(defun heading-twa (wind-dir heading)
  "Compute TWA resulting from HEADING in WIND"
  (normalize-angle (- wind-dir heading)))

(defun twa-boatspeed (forecast polars sails latlon angle)
  (check-type angle angle)
  (multiple-value-bind (wind-dir wind-speed)
      (get-wind-forecast forecast latlon)
    (multiple-value-bind (speed sail)
        (get-max-speed (abs angle) wind-speed polars :options sails)
      (values speed
              (twa-heading wind-dir angle)
              sail
              wind-speed))))

(defun heading-boatspeed (forecast polars sails latlon heading)
  (check-type heading heading)
  (multiple-value-bind (wind-dir wind-speed)
      (get-wind-forecast forecast latlon)
    (let ((angle (heading-twa wind-dir heading)))
      (multiple-value-bind (speed sail)
          (get-max-speed angle wind-speed polars :options sails)
        (values speed angle sail wind-dir wind-speed)))))


(defun parse-datetime-local (time &key (timezone "+01:00"))
  (if (null time)
      (now)
      (parse-rfc3339-timestring (format () "~a:00~a" time timezone))))

;;; Translate latitude coordinates of start and destination to [0..360)
;;; Can't SETF LATLNG-LNG!
#+()(defun gm-to-grib! (latlng)
  (when (< (latlng-lng latlng) 0)
    (incf (latlng-lng latlng) 360)))  

;;; EOF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

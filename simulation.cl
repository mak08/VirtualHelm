;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2015
;;; Last Modified <michael 2017-08-29 23:54:54>

(in-package :virtualhelm)

;;; time in seconds
(defconstant +5min+ (* 5 60))
(defconstant +10min+ (* 10 60))
(defconstant +20min+ (* 20 60))
(defconstant +30min+ (* 30 60))
(defconstant +60min+ (* 60 60))
(defconstant +3h+ (* 3 60 60))
(defconstant +12h+ (* 12 60 60))
(defconstant +24h+ (* 24 60 60))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; A routing stores the start and destination of the route as well as
;;; routing parameters 

(defvar +FEHMARN+
  (make-latlng :lat 54.434403d0 :lng 11.361632d0))

(defvar +YSTAD+
  (make-latlng :lat 55.391123d0 :lng 13.792635d0))
        
(defstruct routing
  (start +fehmarn+)
  (dest +ystad+)
  twapath
  route
  (fan 30)
  (sectors 81)
  (points-per-sector 5)
  (stepmax +30min+)
  (stepsize +10min+))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Isochrones are described by sets of routepoints.
;;;
;;; ### Think of a good sorting/data structure to support finding the most advanced point in a sector

(defstruct routepoint
  position
  heading
  twa
  speed
  sail
  is-land
  predecessor
  destination-angle
  destination-distance)

(defun get-route (routing)
  (let
      ((forecast-bundle (or (get-forecast-bundle 'dwd-icon-bundle)
                            (get-forecast-bundle 'constant-wind-bundle)))
       (step-size (routing-stepsize routing))
       (start-pos (routing-start routing))
       (dest-pos (routing-dest routing)))

    (gm-to-grib! start-pos)
    (gm-to-grib! dest-pos)

    (do* (
          ;; Iteration stops when stepmax seconds have elapsed
          (stepsum 0 (+ stepsum step-size))
          ;; The initial isochrone is just the start point, heading towards destination
          (isochrone (list (make-routepoint :position start-pos
                                            :heading (course-angle start-pos dest-pos)))
                     next-isochrone)
          ;; The next isochrone - in addition we need all hourly isochrones (tbd)

          (next-isochrone)
          ;; Advance the simulation time after each iteration
          (step-time (now) (adjust-timestamp step-time (:offset :sec step-size)))
          ;; Get wind data for simulation time
          (forecast (get-forecast forecast-bundle step-time)
                    (get-forecast forecast-bundle step-time)))
        
        ;; When the maximum number of iterations is reached, construct the best path
        ;; from the most advanced point's predecessor chain.
        ((>= stepsum (routing-stepmax routing))
         (construct-route next-isochrone))
      (log2:info "Isochrone: ~a points" (length isochrone))
      ;; Iterate over each point in the current isochrone
      (map nil
           (lambda (routepoint)
             (let ((left (- (routepoint-heading routepoint) (routing-fan routing)))
                   (right (+ (routepoint-heading routepoint) (routing-fan routing)))
                   (successors (make-array (1+ (* (routing-fan routing) 2)))))
               (loop
                  :for heading :from left :to right
                  :for k :from 0
                  :do (multiple-value-bind (speed angle sail)
                          (heading-boatspeed forecast (routepoint-position routepoint) heading)
                        (let ((new-pos (add-distance-exact (routepoint-position routepoint) (* speed step-size) angle)))
                          (setf (aref successors k)
                                (make-routepoint :position new-pos
                                                 :heading heading
                                                 :twa angle
                                                 :speed speed
                                                 :sail sail
                                                 :is-land (test-point (latlng-lat new-pos) (latlng-lng new-pos))
                                                 :predecessor routepoint
                                                 :destination-angle (course-angle new-pos dest-pos)
                                                 :destination-distance (course-distance new-pos dest-pos))))))
               (setf next-isochrone
                     (concatenate 'vector next-isochrone successors))))
           isochrone))))

(defun construct-route (isochrone)
  isochrone)

(defun get-twa-path (routing
                     &key 
                       (total-time +12h+)
                       (step-num (truncate total-time (routing-stepsize routing))))
  (let* ((forecast-bundle (or (get-forecast-bundle 'dwd-icon-bundle)
                              (get-forecast-bundle 'constant-wind-bundle)))
         (start-time (now))
         (step-time (routing-stepsize routing))
         (startpos (routing-start routing))
         (destpos (routing-dest routing)))
    (gm-to-grib! startpos)
    (gm-to-grib! destpos)
    (let* ((heading (course-angle startpos destpos))
           (curpos (copy-latlng startpos))
           (wind-dir (get-wind-forecast (get-forecast forecast-bundle start-time) startpos))
           (twa (heading-twa wind-dir heading))
           (path nil))
      (dotimes (k step-num (reverse (push (copy-latlng curpos) path)))
        ;; Save current position
        (push (copy-latlng curpos) path)
        (adjust-timestamp! start-time (:offset :sec step-time))
        (let ((forecast (get-forecast forecast-bundle start-time)))
          (multiple-value-bind (speed heading)
              (twa-boatspeed forecast curpos twa)
            (add-distance-exact! curpos (* speed step-time) heading)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; - HEADING values range from 0..360 (clockwise from north)
;;; - ANGLE  values range from -179..180 (starboard downwind to port downwind)  
;;; - DIRECTION values range from -179..180 

(defun twa-heading (wind-dir angle)
  "Compute HEADING resulting from TWA in WIND"
  (let ((heading
         (- wind-dir angle)))
    (if (> heading 360)
        (- heading 360)
        (if (< heading 0)
            (+ heading 360)
            heading))))

(defun heading-twa (wind-dir heading)
  "Compute TWA resulting from HEADING in WIND"
  (let ((angle (- wind-dir heading)))
    (if (<= angle -180)
        (+ angle 360)
        (if (> angle 180)
            (- angle 360)
            angle))))

(defun twa-boatspeed (forecast latlon angle)
  (multiple-value-bind (wind-dir wind-speed)
      (get-wind-forecast forecast latlon)
    (multiple-value-bind (speed sail)
        (get-max-speed (abs angle) wind-speed)
      (values speed
              (twa-heading wind-dir angle)
              sail
              wind-speed))))

(defun heading-boatspeed (forecast latlon heading)
  (multiple-value-bind (wind-dir wind-speed)
      (get-wind-forecast forecast latlon)
    (let ((angle (heading-twa wind-dir heading)))
      (multiple-value-bind (speed sail)
          (get-max-speed (abs angle) wind-speed)
        (values speed angle sail wind-speed)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Unit conversion

(defun knots-to-m/s (knots)
  (* 463d0 (/ knots 900d0)))

(defun m/s-to-knots (m/s)
  (* 900d0 (/ m/s 463d0)))

(defun m/s-to-kM/H (m/s)
  (* m/s 3.6))

;;; Translate latitude coordinates of start and destination to [0..360)
(defun gm-to-grib! (latlng)
  (when (< (latlng-lng latlng) 0)
    (incf (latlng-lng latlng) 360)))  
  
;;; EOF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

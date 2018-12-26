;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2017
;;; Last Modified <michael 2018-12-25 21:39:35>

(in-package :virtualhelm)


(defun polars-json-to-csv (&key
                             (filename  "/home/michael/Repository/VirtualHelm/polars/IMOCA60VVOR17.json"))
  (let* ((saildefs
          (load-polars-json :filename filename :convert-speed nil))
         (pathname (pathname filename))
         (output-directory (append (pathname-directory pathname)
                                   (list (pathname-name pathname))))
         (output-path (make-pathname :directory output-directory)))
    (log2:info "Writing files to ~a" output-path)
    (ensure-directories-exist output-path)
    (loop
       :for saildef :in saildefs
       :do (with-open-file (f (make-pathname :directory output-directory
                                             :name  (sail-name saildef)
                                             :type "csv")
                              :direction :output
                              :if-exists :supersede)
             (write-polars-csv saildef f)))))

(defun write-polars-csv (saildef file)
  (destructuring-bind (twa-length speed-length)
      (array-dimensions (sail-speed saildef))
    (loop
       :for twa :below twa-length
       :do (progn
             (loop
                :for speed :below speed-length
                :do (format file "~a," (aref (sail-speed saildef) twa speed)))
             (format file "~%")))))

(defun probe-wind (time latlng)
  (let ((forecast (get-forecast
                   (get-forecast-bundle 'noaa-bundle)
                   (parse-rfc3339-timestring time))))
    (log2:info "Using ~a" forecast)
    (multiple-value-bind (angle speed)
        (get-wind-forecast forecast latlng)
      (values angle
              (m/s-to-knots speed)))))


(defun compare-speed (polars-name twa tws &optional (options '("reach" "heavy" "light")))
  (let* ((cpolars (get-combined-polars polars-name (encode-options options)))
         (polars (get-polars polars-name))
         (polars-raw (get-polars-raw polars-name))
         (twa-index (position twa (joref polars-raw "twa") :test #'equalp))
         (tws-index (position tws (joref polars-raw "tws") :test #'equalp)))
    (destructuring-bind (speed sail)
        (get-max-speed (cpolars-speed cpolars) twa (knots-to-m/s tws))
      (format t "Compiled:         ~a~%"
              (m/s-to-knots speed))
      (format t "Raw interpolated: ~a~%"
              (loop
                 :for saildef :across  (joref polars-raw "sail")
                 :when (equal (joref saildef "name") sail)
                 :return (get-boat-speed-raw twa tws (joref polars-raw "twa") (joref polars-raw "tws") saildef)))
      (format t "Converted:        ~a~%"
              (m/s-to-knots (get-max-speed% twa (knots-to-m/s tws) polars (encode-options options))))
      (format t "Raw:              ~a~%"
              (when (and twa-index tws-index)
                (loop
                   :for saildef :across  (joref polars-raw "sail")
                   :when (equal (joref saildef "name") sail)
                   :return (aref (aref (joref saildef "speed") twa-index) tws-index))))
      (format t "Sail:             ~a~%"
              sail))))

(defun get-boat-speed-raw (twa tws twa-values tws-values saildef)
  (multiple-value-bind
        (speed-index speed-fraction)
      (fraction-index tws tws-values)
    (multiple-value-bind
          (angle-index angle-fraction)
        (fraction-index twa twa-values)
      (bilinear-unit speed-fraction
                     angle-fraction
                     (aref (aref (joref saildef "speed") angle-index) speed-index)
                     (aref (aref (joref saildef "speed") angle-index) (1+ speed-index))
                     (aref (aref (joref saildef "speed") (1+ angle-index)) speed-index)
                     (aref (aref (joref saildef "speed") (1+ angle-index)) (1+ speed-index))))))

(defun boat-speed-kn (polars-name twa tws &optional (options '("reach" "heavy" "light")))
  (let ((cpolars (get-combined-polars polars-name (encode-options options))))
    (destructuring-bind (speed sail)
        (get-max-speed (cpolars-speed cpolars) twa (knots-to-m/s tws))
      (values (m/s-to-knots speed)
              sail))))


(defun boat-speed-raw (polars-name twa tws &optional (options '("reach" "heavy" "light")))
  (let* ((polars (get-polars-raw polars-name))
         (twa-index (position twa (joref polars "twa") :test #'equalp))
         (tws-index (position tws (joref polars "tws") :test #'equalp))
         (saildefs
          (joref polars "sail")))
    (loop
       :for saildef :across saildefs
       :collect (list (joref saildef "name")
                      (aref (aref (joref saildef "speed") twa-index) tws-index)))))
    

(defvar *polars-raw-ht* (make-hash-table :test #'equal))
(defun get-polars-raw (polars-name)
  (or (gethash polars-name *polars-raw-ht*)
      (setf (gethash polars-name *polars-raw-ht*)
            (joref (joref (parse-json-file polars-name) "scriptData") "polar")))) 
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

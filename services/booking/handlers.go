package booking

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/heena5498/eks-microservices/internal/auth"
	"github.com/heena5498/eks-microservices/internal/repository/bookings"
	"github.com/heena5498/eks-microservices/internal/utils"
)

func (cfg *APIConfig) HandleReadiness(w http.ResponseWriter, r *http.Request) {
	if err := cfg.DB_Conn.Ping(); err != nil {
		utils.RespondWithError(w, http.StatusServiceUnavailable, "Database not ready")
		return
	}

	if err := cfg.RedisClient.client.Ping(r.Context()).Err(); err != nil {
		utils.RespondWithError(w, http.StatusServiceUnavailable, "Redis not ready")
		return
	}

	response := struct {
		Status   string `json:"status"`
		Database string `json:"database"`
		Redis    string `json:"redis"`
	}{
		Status:   "ready",
		Database: "connected",
		Redis:    "connected",
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) CheckAvailability(w http.ResponseWriter, r *http.Request) {
	eventIDStr := r.URL.Query().Get("event_id")
	quantityStr := r.URL.Query().Get("quantity")

	if eventIDStr == "" || quantityStr == "" {
		cfg.Logger.Warn("Availability check with missing parameters")
		utils.RespondWithError(w, http.StatusBadRequest, "event_id and quantity are required")
		return
	}

	eventID, err := uuid.Parse(eventIDStr)
	if err != nil {
		cfg.Logger.WithFields(map[string]any{"event_id_str": eventIDStr, "error": err.Error()}).Warn("Invalid event ID in availability check")
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid event_id format")
		return
	}

	quantity, err := strconv.ParseInt(quantityStr, 10, 32)
	if err != nil || quantity <= 0 {
		cfg.Logger.WithFields(map[string]any{"quantity_str": quantityStr, "event_id": eventID}).Warn("Invalid quantity in availability check")
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid quantity")
		return
	}

	cachedSeats, err := cfg.RedisClient.GetCachedEventAvailability(r.Context(), eventID)
	if err == nil {
		response := CheckAvailabilityResponse{
			Available:      cachedSeats >= int32(quantity),
			AvailableSeats: cachedSeats,
			MaxPerBooking:  10,
			BasePrice:      0.0,
		}
		utils.RespondWithJSON(w, http.StatusOK, response)
		return
	}

	event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), eventID)
	if err != nil {
		cfg.Logger.Error("Failed to get event for availability check",
			"error", err, "event_id", eventID)

		if err.Error() == "event not found or not available for booking" {
			utils.RespondWithError(w, http.StatusNotFound, "Event not found or not available for booking")
		} else {
			utils.RespondWithError(w, http.StatusInternalServerError, "Failed to check event availability")
		}
		return
	}

	cfg.RedisClient.CacheEventAvailability(r.Context(), eventID, event.AvailableSeats, 2*time.Second)
	response := CheckAvailabilityResponse{
		Available:      event.AvailableSeats >= int32(quantity),
		AvailableSeats: event.AvailableSeats,
		MaxPerBooking:  event.MaxTicketsPerBooking,
		BasePrice:      event.BasePrice,
	}

	cfg.Logger.Info("Availability check completed",
		"event_id", eventID,
		"requested_quantity", quantity,
		"available_seats", event.AvailableSeats,
		"available", response.Available)

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) ReserveSeats(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	var req ReservationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		cfg.Logger.WithFields(map[string]any{"error": err.Error(), "user_id": userID}).Warn("Invalid JSON in seat reservation")
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid JSON")
		return
	}

	if req.EventID == uuid.Nil || req.Quantity <= 0 || req.IdempotencyKey == "" {
		cfg.Logger.WithFields(map[string]any{"user_id": userID, "event_id": req.EventID, "quantity": req.Quantity}).Warn("Seat reservation with missing required fields")
		utils.RespondWithError(w, http.StatusBadRequest, "event_id, quantity, and idempotency_key are required")
		return
	}

	if req.Quantity > int32(cfg.Config.MaxTicketsPerUser) {
		cfg.Logger.WithFields(map[string]any{"user_id": userID, "event_id": req.EventID, "quantity": req.Quantity, "max_allowed": cfg.Config.MaxTicketsPerUser}).Warn("Seat reservation exceeds maximum allowed")
		utils.RespondWithError(w, http.StatusBadRequest, fmt.Sprintf("Maximum %d tickets allowed per booking", cfg.Config.MaxTicketsPerUser))
		return
	}

	allowed, err := cfg.RedisClient.CheckRateLimit(r.Context(), userID, int64(cfg.Config.RateLimitPerMinute))
	if err != nil {
		cfg.Logger.Error("Rate limit check failed", "error", err, "user_id", userID)
	} else if !allowed {
		utils.RespondWithError(w, http.StatusTooManyRequests, "Too many booking attempts. Please try again later.")
		return
	}

	cfg.RedisClient.IncrementRateLimit(r.Context(), userID, time.Minute)

	existingBooking, err := cfg.DB.GetBookingByIdempotencyKey(r.Context(), cfg.DB_Conn, sql.NullString{String: req.IdempotencyKey, Valid: true})
	if err == nil {
		cfg.Logger.Info("Idempotent booking request", "idempotency_key", req.IdempotencyKey, "existing_booking_id", existingBooking.BookingID)

		response := ReservationResponse{
			ReservationID:    existingBooking.BookingID,
			BookingReference: existingBooking.BookingReference,
			ExpiresAt:        existingBooking.ExpiresAt.Time,
			TotalAmount:      utils.ParseAmount(existingBooking.TotalAmount),
		}
		utils.RespondWithJSON(w, http.StatusOK, response)
		return
	}

	cachedEvent, cacheErr := cfg.RedisClient.GetCachedEventMetadata(r.Context(), req.EventID)
	if cacheErr != nil {
		event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), req.EventID)
		if err != nil {
			cfg.Logger.Error("Failed to get event for reservation", "error", err, "event_id", req.EventID)
			utils.RespondWithError(w, http.StatusBadRequest, "Event not found or not available for booking")
			return
		}
		cfg.RedisClient.CacheEventMetadata(r.Context(), req.EventID, event, 5*time.Minute)
		cachedEvent = event
	}

	if req.Quantity > cachedEvent.MaxTicketsPerBooking {
		utils.RespondWithError(w, http.StatusBadRequest, fmt.Sprintf("Maximum %d tickets allowed per booking for this event", cachedEvent.MaxTicketsPerBooking))
		return
	}

	event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), req.EventID)
	if err != nil {
		cfg.Logger.Error("Failed to get fresh event data", "error", err, "event_id", req.EventID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to verify event availability")
		return
	}

	isWaitlistUser := false
	userWaitlistEntry, err := cfg.DB.GetWaitlistEntryByUserAndEvent(r.Context(), cfg.DB_Conn, bookings.GetWaitlistEntryByUserAndEventParams{
		UserID:  userID,
		EventID: req.EventID,
	})
	if err == nil && userWaitlistEntry.Status.String == "offered" {
		if userWaitlistEntry.ExpiresAt.Valid && time.Now().Before(userWaitlistEntry.ExpiresAt.Time) {
			isWaitlistUser = true
			cfg.Logger.Info("Waitlist user booking", "user_id", userID, "event_id", req.EventID)
		}
	}

	updateResp, err := cfg.EventServiceClient.UpdateAvailability(r.Context(), req.EventID, -req.Quantity, event.Version)
	if err != nil {
		cfg.Logger.Error("Failed to reserve seats", "error", err, "event_id", req.EventID, "quantity", req.Quantity, "version", event.Version)

		if strings.Contains(err.Error(), "Not enough seats available") {
			utils.RespondWithError(w, http.StatusConflict, "Not enough seats available")
		} else if strings.Contains(err.Error(), "updated by another process") {
			utils.RespondWithError(w, http.StatusConflict, "Event was updated by another process. Please retry.")
		} else {
			utils.RespondWithError(w, http.StatusInternalServerError, "Failed to reserve seats")
		}
		return
	}

	totalAmount := event.BasePrice * float64(req.Quantity)
	bookingRef := utils.GenerateBookingReference()

	var expiresAt time.Time
	var reservationExpiry time.Duration

	if isWaitlistUser {
		cfg.Logger.Info("Waitlist user booking reservation", "user_id", userID, "event_id", req.EventID)
		expiresAt = userWaitlistEntry.ExpiresAt.Time
		reservationExpiry = time.Until(expiresAt)
	} else {
		cfg.Logger.Info("Regular user booking reservation", "user_id", userID, "event_id", req.EventID)
		expiresAt = time.Now().Add(cfg.Config.ReservationExpiry)
		reservationExpiry = cfg.Config.ReservationExpiry
	}

	booking, err := cfg.DB.CreateBooking(r.Context(), cfg.DB_Conn, bookings.CreateBookingParams{
		UserID:           userID,
		EventID:          req.EventID,
		BookingReference: bookingRef,
		Quantity:         req.Quantity,
		TotalAmount:      fmt.Sprintf("%.2f", totalAmount),
		Status:           "pending",
		PaymentStatus:    "pending",
		IdempotencyKey:   sql.NullString{String: req.IdempotencyKey, Valid: true},
		ExpiresAt:        sql.NullTime{Time: expiresAt, Valid: true},
	})
	if err != nil {
		cfg.Logger.Error("Failed to create booking", "error", err)
		cfg.EventServiceClient.ReturnSeats(r.Context(), req.EventID, req.Quantity, updateResp.Version)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to create booking")
		return
	}

	reservationData := &ReservationData{
		UserID:           userID,
		EventID:          req.EventID,
		Quantity:         req.Quantity,
		Amount:           totalAmount,
		BookingID:        booking.BookingID,
		BookingReference: bookingRef,
		ExpiresAt:        expiresAt,
	}

	if err := cfg.RedisClient.SetReservation(r.Context(), booking.BookingID, reservationData, reservationExpiry); err != nil {
		cfg.Logger.Error("Failed to store reservation in Redis", "error", err, "booking_id", booking.BookingID)
	}

	cfg.Logger.Info("Seats reserved successfully",
		"booking_id", booking.BookingID,
		"user_id", userID,
		"event_id", req.EventID,
		"quantity", req.Quantity,
		"expires_at", expiresAt)

	response := ReservationResponse{
		ReservationID:    booking.BookingID,
		BookingReference: bookingRef,
		ExpiresAt:        expiresAt,
		TotalAmount:      totalAmount,
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) ConfirmBooking(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	var req ConfirmationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		cfg.Logger.WithFields(map[string]any{"error": err.Error(), "user_id": userID}).Warn("Invalid JSON in booking confirmation")
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid JSON")
		return
	}

	if req.ReservationID == uuid.Nil {
		cfg.Logger.WithFields(map[string]any{"user_id": userID, "reservation_id": req.ReservationID}).Warn("Booking confirmation with missing reservation_id")
		utils.RespondWithError(w, http.StatusBadRequest, "reservation_id is required")
		return
	}

	// Campus event system - no payment processing required
	// PaymentToken and PaymentMethod are optional for free campus events

	var booking bookings.Booking

	reservation, err := cfg.RedisClient.GetReservation(r.Context(), req.ReservationID)
	if err != nil {
		cfg.Logger.Warn("Redis unavailable, falling back to database",
			"error", err, "reservation_id", req.ReservationID)

		booking, err = cfg.DB.GetBookingByID(r.Context(), cfg.DB_Conn, req.ReservationID)
		if err != nil {
			cfg.Logger.Error("Failed to get booking from database", "error", err, "booking_id", req.ReservationID)
			utils.RespondWithError(w, http.StatusNotFound, "Booking not found")
			return
		}

		if booking.UserID != userID {
			utils.RespondWithError(w, http.StatusForbidden, "Reservation does not belong to authenticated user")
			return
		}

		if booking.Status != "pending" {
			utils.RespondWithError(w, http.StatusConflict, "Booking is not in pending state")
			return
		}

		if booking.ExpiresAt.Valid && time.Now().After(booking.ExpiresAt.Time) {
			cfg.Logger.Info("Booking expired during payment attempt",
				"booking_id", req.ReservationID, "expired_at", booking.ExpiresAt.Time)
			utils.RespondWithError(w, http.StatusBadRequest, "Reservation has expired")
			return
		}

		cfg.Logger.Info("Database fallback successful", "booking_id", req.ReservationID)
	} else {
		if reservation.UserID != userID {
			utils.RespondWithError(w, http.StatusForbidden, "Reservation does not belong to authenticated user")
			return
		}

		booking, err = cfg.DB.GetBookingByID(r.Context(), cfg.DB_Conn, req.ReservationID)
		if err != nil {
			cfg.Logger.Error("Failed to get booking", "error", err, "booking_id", req.ReservationID)
			utils.RespondWithError(w, http.StatusNotFound, "Booking not found")
			return
		}

		if booking.Status != "pending" {
			utils.RespondWithError(w, http.StatusConflict, "Booking is not in pending state")
			return
		}
	}

	// Campus event system - skip payment processing for free events
	ticketURL := utils.GenerateTicketURL(booking.BookingReference)
	cfg.Logger.Info("Confirming campus event booking without payment",
		"booking_id", booking.BookingID,
		"user_id", userID,
		"event_id", booking.EventID)

	_, err = cfg.DB.UpdateBookingStatus(r.Context(), cfg.DB_Conn, bookings.UpdateBookingStatusParams{
		BookingID: booking.BookingID,
		Status:    "confirmed",
	})
	if err != nil {
		cfg.Logger.Error("Failed to update booking status", "error", err)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to confirm booking")
		return
	}

	// Campus event system - no separate payment tracking needed
	cfg.Logger.Info("Campus event booking confirmed without payment processing",
		"booking_id", booking.BookingID,
		"status", "confirmed")

	cfg.RedisClient.DeleteReservation(r.Context(), req.ReservationID)
	cfg.RedisClient.InvalidateEventAvailabilityCache(r.Context(), booking.EventID)

	userWaitlistEntry, err := cfg.DB.GetWaitlistEntryByUserAndEvent(r.Context(), cfg.DB_Conn, bookings.GetWaitlistEntryByUserAndEventParams{
		UserID:  userID,
		EventID: booking.EventID,
	})
	if err == nil && userWaitlistEntry.Status.String == "offered" {
		_, err = cfg.DB.UpdateWaitlistStatus(r.Context(), cfg.DB_Conn, bookings.UpdateWaitlistStatusParams{
			WaitlistID: userWaitlistEntry.WaitlistID,
			Status:     sql.NullString{String: "converted", Valid: true},
			ExpiresAt:  sql.NullTime{Valid: false},
		})
		if err != nil {
			cfg.Logger.Error("Failed to convert waitlist status", "error", err, "user_id", userID)
		} else {
			cfg.Logger.Info("Waitlist user converted to booking", "user_id", userID, "event_id", booking.EventID)
		}
	}

	cfg.Logger.Info("Booking confirmed successfully",
		"booking_id", booking.BookingID,
		"user_id", userID,
		"event_id", booking.EventID)

	response := ConfirmationResponse{
		BookingID:        booking.BookingID,
		BookingReference: booking.BookingReference,
		Status:           "confirmed",
		TicketURL:        ticketURL,
		Payment: PaymentInfo{
			TransactionID: "CAMPUS-FREE-" + booking.BookingReference,
			Status:        "completed",
			Amount:        utils.ParseAmount(booking.TotalAmount),
		},
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) GetBookingDetails(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	bookingIDStr := r.PathValue("id")
	bookingID, err := uuid.Parse(bookingIDStr)
	if err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid booking ID format")
		return
	}

	booking, err := cfg.DB.GetBookingByID(r.Context(), cfg.DB_Conn, bookingID)
	if err != nil {
		cfg.Logger.Error("Failed to get booking", "error", err, "booking_id", bookingID)
		utils.RespondWithError(w, http.StatusNotFound, "Booking not found")
		return
	}

	if booking.UserID != userID {
		utils.RespondWithError(w, http.StatusForbidden, "Access denied")
		return
	}

	event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), booking.EventID)
	if err != nil {
		cfg.Logger.Error("Failed to get event details", "error", err, "event_id", booking.EventID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to get event details")
		return
	}

	response := BookingDetailsResponse{
		BookingID:        booking.BookingID,
		BookingReference: booking.BookingReference,
		Event: EventInfo{
			Name:     event.Name,
			Venue:    "Event Venue",
			DateTime: time.Now().Add(24 * time.Hour),
		},
		Quantity:      booking.Quantity,
		TotalAmount:   utils.ParseAmount(booking.TotalAmount),
		Status:        booking.Status,
		PaymentStatus: booking.PaymentStatus,
		BookedAt:      booking.BookedAt.Time,
	}

	if booking.ConfirmedAt.Valid {
		response.ConfirmedAt = &booking.ConfirmedAt.Time
	}

	// For campus events, ticket URL is generated on confirmation
	// No separate payment tracking

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) CancelBooking(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	bookingIDStr := r.PathValue("id")
	bookingID, err := uuid.Parse(bookingIDStr)
	if err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid booking ID format")
		return
	}

	booking, err := cfg.DB.GetBookingByID(r.Context(), cfg.DB_Conn, bookingID)
	if err != nil {
		cfg.Logger.Error("Failed to get booking", "error", err, "booking_id", bookingID)
		utils.RespondWithError(w, http.StatusNotFound, "Booking not found")
		return
	}

	if booking.UserID != userID {
		utils.RespondWithError(w, http.StatusForbidden, "Access denied")
		return
	}

	if booking.Status == "cancelled" {
		utils.RespondWithError(w, http.StatusConflict, "Booking is already cancelled")
		return
	}

	if booking.Status == "expired" {
		utils.RespondWithError(w, http.StatusConflict, "Cannot cancel expired booking")
		return
	}

	originalAmount := utils.ParseAmount(booking.TotalAmount)
	refundAmount := utils.CalculateRefundAmount(originalAmount, booking.BookedAt.Time, time.Now().Add(48*time.Hour))

	_, err = cfg.DB.UpdateBookingStatus(r.Context(), cfg.DB_Conn, bookings.UpdateBookingStatusParams{
		BookingID: bookingID,
		Status:    "cancelled",
	})
	if err != nil {
		cfg.Logger.Error("Failed to cancel booking", "error", err, "booking_id", bookingID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to cancel booking")
		return
	}

	if booking.Status == "confirmed" {
		event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), booking.EventID)
		if err != nil {
			cfg.Logger.Error("Failed to get event for cancellation", "error", err, "event_id", booking.EventID)
		} else {
			_, err = cfg.EventServiceClient.ReturnSeats(r.Context(), booking.EventID, booking.Quantity, event.Version)
			if err != nil {
				cfg.Logger.Error("Failed to return seats", "error", err, "booking_id", bookingID)
			}
		}

		cfg.ProcessWaitlist(r.Context(), booking.EventID, booking.Quantity)
	}

	refundStatus := "none"
	if refundAmount > 0 {
		refundStatus = "processed"
	}

	cfg.RedisClient.DeleteReservation(r.Context(), bookingID)
	cfg.RedisClient.InvalidateEventAvailabilityCache(r.Context(), booking.EventID)

	cfg.Logger.Info("Booking cancelled",
		"booking_id", bookingID,
		"user_id", userID,
		"refund_amount", refundAmount)

	response := CancellationResponse{
		Message:      "Booking cancelled successfully",
		RefundStatus: refundStatus,
		RefundAmount: refundAmount,
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) GetUserBookings(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page <= 0 {
		page = 1
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 10
	}

	offset := (page - 1) * limit

	userBookings, err := cfg.DB.GetUserBookings(r.Context(), cfg.DB_Conn, bookings.GetUserBookingsParams{
		UserID: userID,
		Limit:  int32(limit),
		Offset: int32(offset),
	})
	if err != nil {
		cfg.Logger.Error("Failed to get user bookings", "error", err, "user_id", userID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to get bookings")
		return
	}

	total, err := cfg.DB.GetUserBookingsCount(r.Context(), cfg.DB_Conn, userID)
	if err != nil {
		cfg.Logger.Error("Failed to get user bookings count", "error", err, "user_id", userID)
		total = 0
	}

	bookingList := make([]BookingDetailsResponse, len(userBookings))
	for i, booking := range userBookings {
		bookingList[i] = BookingDetailsResponse{
			BookingID:        booking.BookingID,
			BookingReference: booking.BookingReference,
			Quantity:         booking.Quantity,
			TotalAmount:      utils.ParseAmount(booking.TotalAmount),
			Status:           booking.Status,
			PaymentStatus:    booking.PaymentStatus,
			BookedAt:         booking.BookedAt.Time,
		}

		if booking.ConfirmedAt.Valid {
			bookingList[i].ConfirmedAt = &booking.ConfirmedAt.Time
		}
	}

	response := map[string]any{
		"bookings":    bookingList,
		"total":       total,
		"page":        page,
		"limit":       limit,
		"total_pages": (int(total) + limit - 1) / limit,
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) GetPendingReservationForEvent(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	eventIDStr := r.PathValue("eventId")
	eventID, err := uuid.Parse(eventIDStr)
	if err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid event ID")
		return
	}

	booking, err := cfg.DB.GetPendingBookingByUserAndEvent(r.Context(), cfg.DB_Conn, bookings.GetPendingBookingByUserAndEventParams{
		UserID:  userID,
		EventID: eventID,
	})
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondWithError(w, http.StatusNotFound, "No pending reservation found")
			return
		}
		cfg.Logger.Error("Failed to get pending reservation", "error", err, "user_id", userID, "event_id", eventID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to get reservation")
		return
	}

	if booking.ExpiresAt.Valid && time.Now().After(booking.ExpiresAt.Time) {
		utils.RespondWithError(w, http.StatusNotFound, "Reservation has expired")
		return
	}

	response := ReservationResponse{
		ReservationID:    booking.BookingID,
		BookingReference: booking.BookingReference,
		ExpiresAt:        booking.ExpiresAt.Time,
		TotalAmount:      utils.ParseAmount(booking.TotalAmount),
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) JoinWaitlist(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	var req JoinWaitlistRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid JSON")
		return
	}

	if req.EventID == uuid.Nil || req.Quantity <= 0 {
		utils.RespondWithError(w, http.StatusBadRequest, "event_id and quantity are required")
		return
	}

	existingEntry, err := cfg.DB.GetWaitlistEntryByUserAndEvent(r.Context(), cfg.DB_Conn, bookings.GetWaitlistEntryByUserAndEventParams{
		UserID:  userID,
		EventID: req.EventID,
	})
	if err == nil {
		var position int32
		if existingEntry.Status.String == "waiting" {
			posResult, posErr := cfg.DB.GetWaitlistPosition(r.Context(), cfg.DB_Conn, bookings.GetWaitlistPositionParams{
				UserID:  userID,
				EventID: req.EventID,
			})
			if posErr == nil {
				position = int32(posResult.Position)
			}
		}
		response := JoinWaitlistResponse{
			WaitlistID:    existingEntry.WaitlistID,
			Position:      position,
			EstimatedWait: cfg.calculateEstimatedWait(position),
			Status:        existingEntry.Status.String,
		}
		utils.RespondWithJSON(w, http.StatusOK, response)
		return
	}

	event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), req.EventID)
	if err != nil {
		cfg.Logger.Error("Failed to get event for waitlist", "error", err, "event_id", req.EventID)
		utils.RespondWithError(w, http.StatusBadRequest, "Event not found")
		return
	}

	if event.AvailableSeats >= req.Quantity {
		utils.RespondWithError(w, http.StatusBadRequest, "Seats are available, please book directly")
		return
	}

	waitlistEntry, err := cfg.DB.JoinWaitlist(r.Context(), cfg.DB_Conn, bookings.JoinWaitlistParams{
		EventID:           req.EventID,
		UserID:            userID,
		QuantityRequested: req.Quantity,
	})
	if err != nil {
		cfg.Logger.Error("Failed to join waitlist", "error", err, "user_id", userID, "event_id", req.EventID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to join waitlist")
		return
	}

	cfg.RedisClient.InvalidateWaitlistCache(r.Context(), req.EventID)

	stats, err := cfg.DB.GetWaitlistStats(r.Context(), cfg.DB_Conn, req.EventID)
	if err != nil {
		cfg.Logger.Error("Failed to get waitlist stats", "error", err)
		stats.TotalWaiting = 0
	}

	position := int32(stats.TotalWaiting)

	cfg.Logger.Info("User joined waitlist",
		"user_id", userID,
		"event_id", req.EventID,
		"position", position,
		"quantity", req.Quantity)

	response := JoinWaitlistResponse{
		WaitlistID:    waitlistEntry.WaitlistID,
		Position:      position,
		EstimatedWait: cfg.calculateEstimatedWait(position),
		Status:        "waiting",
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) GetWaitlistPosition(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	eventIDStr := r.URL.Query().Get("event_id")
	if eventIDStr == "" {
		utils.RespondWithError(w, http.StatusBadRequest, "event_id is required")
		return
	}

	eventID, err := uuid.Parse(eventIDStr)
	if err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid event_id format")
		return
	}

	cachedPosition, err := cfg.RedisClient.GetCachedWaitlistPosition(r.Context(), eventID, userID)
	if err == nil {
		utils.RespondWithJSON(w, http.StatusOK, cachedPosition)
		return
	}

	waitlistEntry, err := cfg.DB.GetWaitlistEntryByUserAndEvent(r.Context(), cfg.DB_Conn, bookings.GetWaitlistEntryByUserAndEventParams{
		UserID:  userID,
		EventID: eventID,
	})
	if err != nil {
		utils.RespondWithError(w, http.StatusNotFound, "Not in waitlist for this event")
		return
	}

	stats, err := cfg.DB.GetWaitlistStats(r.Context(), cfg.DB_Conn, eventID)
	if err != nil {
		cfg.Logger.Error("Failed to get waitlist stats", "error", err, "event_id", eventID)
		stats.TotalWaiting = 0
	}

	var position int32
	if waitlistEntry.Status.String == "waiting" {
		posResult, err := cfg.DB.GetWaitlistPosition(r.Context(), cfg.DB_Conn, bookings.GetWaitlistPositionParams{
			UserID:  userID,
			EventID: eventID,
		})
		if err != nil {
			cfg.Logger.Error("Failed to get position", "error", err)
			position = 0
		} else {
			position = int32(posResult.Position)
		}
	}

	response := WaitlistPositionResponse{
		Position:          position,
		TotalWaiting:      int32(stats.TotalWaiting),
		Status:            waitlistEntry.Status.String,
		EstimatedWait:     cfg.calculateEstimatedWait(position),
		QuantityRequested: waitlistEntry.QuantityRequested,
	}

	if waitlistEntry.Status.String == "offered" {
		if waitlistEntry.ExpiresAt.Valid {
			response.ExpiresAt = &waitlistEntry.ExpiresAt.Time
		}
		if waitlistEntry.OfferedAt.Valid {
			response.OfferedAt = &waitlistEntry.OfferedAt.Time
		}
	}

	cfg.RedisClient.CacheWaitlistPosition(r.Context(), eventID, userID, response)

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) LeaveWaitlist(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	var req LeaveWaitlistRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid JSON")
		return
	}

	if req.EventID == uuid.Nil {
		utils.RespondWithError(w, http.StatusBadRequest, "event_id is required")
		return
	}

	_, err := cfg.DB.GetWaitlistEntryByUserAndEvent(r.Context(), cfg.DB_Conn, bookings.GetWaitlistEntryByUserAndEventParams{
		UserID:  userID,
		EventID: req.EventID,
	})
	if err != nil {
		utils.RespondWithError(w, http.StatusNotFound, "Not in waitlist for this event")
		return
	}

	err = cfg.DB.RemoveFromWaitlist(r.Context(), cfg.DB_Conn, bookings.RemoveFromWaitlistParams{
		UserID:  userID,
		EventID: req.EventID,
	})
	if err != nil {
		cfg.Logger.Error("Failed to remove from waitlist", "error", err, "user_id", userID, "event_id", req.EventID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to leave waitlist")
		return
	}

	cfg.RedisClient.InvalidateWaitlistCache(r.Context(), req.EventID)

	cfg.Logger.Info("User left waitlist",
		"user_id", userID,
		"event_id", req.EventID)

	response := map[string]string{
		"message": "Successfully removed from waitlist",
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) GetBookingInternal(w http.ResponseWriter, r *http.Request) {
	bookingIDStr := r.PathValue("id")
	bookingID, err := uuid.Parse(bookingIDStr)
	if err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid booking ID format")
		return
	}

	booking, err := cfg.DB.GetBookingByID(r.Context(), cfg.DB_Conn, bookingID)
	if err != nil {
		cfg.Logger.Error("Failed to get booking", "error", err, "booking_id", bookingID)
		utils.RespondWithError(w, http.StatusNotFound, "Booking not found")
		return
	}

	response := map[string]any{
		"booking_id":        booking.BookingID,
		"user_id":           booking.UserID,
		"event_id":          booking.EventID,
		"booking_reference": booking.BookingReference,
		"quantity":          booking.Quantity,
		"total_amount":      utils.ParseAmount(booking.TotalAmount),
		"status":            booking.Status,
		"payment_status":    booking.PaymentStatus,
		"booked_at":         booking.BookedAt,
	}

	if booking.ConfirmedAt.Valid {
		response["confirmed_at"] = booking.ConfirmedAt.Time
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) ExpireReservations(w http.ResponseWriter, r *http.Request) {
	expiredBookings, err := cfg.DB.GetExpiredBookings(r.Context(), cfg.DB_Conn, 100)
	if err != nil {
		cfg.Logger.Error("Failed to get expired bookings", "error", err)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to process expired reservations")
		return
	}

	processed := 0
	for _, booking := range expiredBookings {
		_, err := cfg.DB.UpdateBookingStatus(r.Context(), cfg.DB_Conn, bookings.UpdateBookingStatusParams{
			BookingID: booking.BookingID,
			Status:    "expired",
		})
		if err != nil {
			cfg.Logger.Error("Failed to expire booking", "error", err, "booking_id", booking.BookingID)
			continue
		}

		event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), booking.EventID)
		if err != nil {
			cfg.Logger.Error("Failed to get event for seat return", "error", err, "event_id", booking.EventID)
		} else {
			_, err = cfg.EventServiceClient.ReturnSeats(r.Context(), booking.EventID, booking.Quantity, event.Version)
			if err != nil {
				cfg.Logger.Error("Failed to return seats", "error", err, "booking_id", booking.BookingID, "event_id", booking.EventID)
			}
		}

		cfg.RedisClient.DeleteReservation(r.Context(), booking.BookingID)
		cfg.RedisClient.InvalidateEventAvailabilityCache(r.Context(), booking.EventID)
		processed++

		cfg.Logger.Info("Expired booking processed",
			"booking_id", booking.BookingID,
			"event_id", booking.EventID,
			"quantity", booking.Quantity)

		cfg.ProcessWaitlist(r.Context(), booking.EventID, booking.Quantity)
	}

	response := map[string]any{
		"processed": processed,
		"total":     len(expiredBookings),
	}

	cfg.ExpireWaitlistOffers(r.Context())

	cfg.Logger.Info("Reservation expiry job completed", "processed", processed, "total", len(expiredBookings))
	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) ForceExpireAll(w http.ResponseWriter, r *http.Request) {
	allPendingBookings, err := cfg.DB.GetPendingBookings(r.Context(), cfg.DB_Conn, 1000)
	if err != nil {
		cfg.Logger.Error("Failed to get pending bookings for force expiry", "error", err)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to get pending bookings")
		return
	}

	processed := 0
	for _, booking := range allPendingBookings {
		_, err := cfg.DB.UpdateBookingStatus(r.Context(), cfg.DB_Conn, bookings.UpdateBookingStatusParams{
			BookingID: booking.BookingID,
			Status:    "expired",
		})
		if err != nil {
			cfg.Logger.Error("Failed to force expire booking", "error", err, "booking_id", booking.BookingID)
			continue
		}

		event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), booking.EventID)
		if err != nil {
			cfg.Logger.Error("Failed to get event for seat return in force expiry", "error", err, "event_id", booking.EventID)
		} else {
			_, err = cfg.EventServiceClient.ReturnSeats(r.Context(), booking.EventID, booking.Quantity, event.Version)
			if err != nil {
				cfg.Logger.Error("Failed to return seats in force expiry", "error", err, "booking_id", booking.BookingID, "event_id", booking.EventID)
			}
		}

		cfg.RedisClient.DeleteReservation(r.Context(), booking.BookingID)
		cfg.RedisClient.InvalidateEventAvailabilityCache(r.Context(), booking.EventID)
		processed++

		cfg.Logger.Info("Force expired booking",
			"booking_id", booking.BookingID,
			"event_id", booking.EventID,
			"quantity", booking.Quantity)

		cfg.ProcessWaitlist(r.Context(), booking.EventID, booking.Quantity)
	}

	response := map[string]any{
		"message":   "Force expired all pending reservations",
		"processed": processed,
		"total":     len(allPendingBookings),
	}

	cfg.ExpireWaitlistOffers(r.Context())

	cfg.Logger.Info("Force expiry job completed", "processed", processed, "total", len(allPendingBookings))
	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) ManualExpireReservation(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		utils.RespondWithError(w, http.StatusUnauthorized, "User not authenticated")
		return
	}

	bookingIDStr := r.PathValue("id")
	bookingID, err := uuid.Parse(bookingIDStr)
	if err != nil {
		utils.RespondWithError(w, http.StatusBadRequest, "Invalid booking ID format")
		return
	}

	booking, err := cfg.DB.GetBookingByID(r.Context(), cfg.DB_Conn, bookingID)
	if err != nil {
		cfg.Logger.Error("Failed to get booking for manual expiry", "error", err, "booking_id", bookingID)
		utils.RespondWithError(w, http.StatusNotFound, "Booking not found")
		return
	}

	if booking.UserID != userID {
		utils.RespondWithError(w, http.StatusForbidden, "Access denied")
		return
	}

	if booking.Status != "pending" {
		utils.RespondWithError(w, http.StatusConflict, "Only pending bookings can be manually expired")
		return
	}

	_, err = cfg.DB.UpdateBookingStatus(r.Context(), cfg.DB_Conn, bookings.UpdateBookingStatusParams{
		BookingID: bookingID,
		Status:    "expired",
	})
	if err != nil {
		cfg.Logger.Error("Failed to expire booking manually", "error", err, "booking_id", bookingID)
		utils.RespondWithError(w, http.StatusInternalServerError, "Failed to expire booking")
		return
	}

	event, err := cfg.EventServiceClient.GetEventForBooking(r.Context(), booking.EventID)
	if err != nil {
		cfg.Logger.Error("Failed to get event for manual seat return", "error", err, "event_id", booking.EventID)
	} else {
		_, err = cfg.EventServiceClient.ReturnSeats(r.Context(), booking.EventID, booking.Quantity, event.Version)
		if err != nil {
			cfg.Logger.Error("Failed to return seats manually", "error", err, "booking_id", bookingID, "event_id", booking.EventID)
		}
	}

	cfg.RedisClient.DeleteReservation(r.Context(), bookingID)
	cfg.RedisClient.InvalidateEventAvailabilityCache(r.Context(), booking.EventID)

	cfg.ProcessWaitlist(r.Context(), booking.EventID, booking.Quantity)

	cfg.Logger.Info("Booking manually expired",
		"booking_id", bookingID,
		"user_id", userID,
		"event_id", booking.EventID,
		"quantity", booking.Quantity)

	response := map[string]string{
		"message": "Reservation expired successfully",
	}

	utils.RespondWithJSON(w, http.StatusOK, response)
}

func (cfg *APIConfig) calculateEstimatedWait(position int32) string {
	if position == 1 {
		return "Next in line"
	} else if position <= 5 {
		return "5-15 minutes"
	} else if position <= 20 {
		return "15-60 minutes"
	}
	return "More than 1 hour"
}

func (cfg *APIConfig) ProcessWaitlist(ctx context.Context, eventID uuid.UUID, availableSeats int32) {
	if availableSeats <= 0 {
		return
	}

	nextEntries, err := cfg.DB.GetNextWaitlistEntries(ctx, cfg.DB_Conn, bookings.GetNextWaitlistEntriesParams{
		EventID: eventID,
		Limit:   availableSeats * 2,
	})
	if err != nil {
		cfg.Logger.Error("Failed to get waitlist entries", "error", err, "event_id", eventID)
		return
	}

	if len(nextEntries) == 0 {
		return
	}

	offersCreated := false
	seatsToOffer := availableSeats
	for _, entry := range nextEntries {
		if seatsToOffer <= 0 {
			break
		}

		if entry.QuantityRequested <= seatsToOffer || seatsToOffer == availableSeats {
			expiresAt := time.Now().Add(2 * time.Minute)

			_, err := cfg.DB.SetWaitlistOffered(ctx, cfg.DB_Conn, bookings.SetWaitlistOfferedParams{
				WaitlistID: entry.WaitlistID,
				ExpiresAt:  sql.NullTime{Time: expiresAt, Valid: true},
			})
			if err != nil {
				cfg.Logger.Error("Failed to update waitlist status", "error", err, "waitlist_id", entry.WaitlistID)
				continue
			}

			offersCreated = true

			cfg.Logger.Info("Waitlist offer created",
				"user_id", entry.UserID,
				"event_id", eventID,
				"seats_offered", min(entry.QuantityRequested, seatsToOffer),
				"expires_at", expiresAt)

			cfg.Logger.Info("Notification: Waitlist seats available",
				"type", "waitlist_offer",
				"user_id", entry.UserID,
				"event_id", eventID,
				"expires_at", expiresAt)

			seatsToOffer -= min(entry.QuantityRequested, seatsToOffer)
		}
	}

	if offersCreated {
		cfg.RedisClient.InvalidateWaitlistCache(ctx, eventID)
	}
}

func (cfg *APIConfig) ExpireWaitlistOffers(ctx context.Context) error {
	expiredOffers, err := cfg.DB.GetExpiredWaitlistOffers(ctx, cfg.DB_Conn)
	if err != nil {
		return err
	}

	for _, offer := range expiredOffers {
		_, err = cfg.DB.SetWaitlistWaiting(ctx, cfg.DB_Conn, offer.WaitlistID)
		if err != nil {
			cfg.Logger.Error("Failed to expire waitlist offer", "error", err, "waitlist_id", offer.WaitlistID)
			continue
		}

		cfg.Logger.Info("Waitlist offer expired - user back in queue",
			"user_id", offer.UserID,
			"event_id", offer.EventID)
	}

	return nil
}

func min(a, b int32) int32 {
	if a < b {
		return a
	}
	return b
}

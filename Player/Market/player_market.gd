extends Player
class_name PlayerMarket

## Emitted once a customer's item/opening offer is known, so the UI can set up
## the dialog label, configure the price slider, and highlight the wanted fish.
signal negotiation_started(customer : Customer)
## Emitted whenever the customer has something new to say.
signal dialog_updated(text : String)
## Emitted once a customer is fully resolved (sold or walked away) and the UI
## should refresh the inventory grid and unlock all fish buttons again.
signal deal_finished()

var active_customer : Customer = null
var requested_amount : float = 0.0
var _slider_touched : bool = false

## Wire to the "Offer" button's `pressed` signal
@export var market : GameMarket


func start_negotiating(customer : Customer) -> void:
	active_customer = customer
	_slider_touched = false
	if not customer.request_random_item(UtilityStates.items):
		var request_text := customer.generate_request_text()
		if request_text.is_empty():
			request_text = "%s wants an item you don't have." % customer.display_name
		UtilityStates.requests.append(request_text)
		dialog_updated.emit(request_text)

		active_customer = null
		if market:
			market.play_exit_animation("End", func():
				market.on_customer_done()
				deal_finished.emit()
			)
		return

	requested_amount = active_customer.get_current_offer()
	print("%s wants your %s" % [customer.display_name, customer.ask_item()])
	negotiation_started.emit(active_customer)


## Wire to the slider's `value_changed` signal (via UserInterface)
func set_requested_amount(value : float) -> void:
	requested_amount = value
	_slider_touched = true


func accept_deal() -> void:
	if active_customer == null or active_customer.want_item == null:
		return

	var item := active_customer.want_item
	var price := active_customer.get_current_offer()
	var customer_name := active_customer.display_name

	if UtilityStates.remove_item(item):
		# UtilityStates.money += price
		print("Sold %s for %.2f" % [item.display_name, price])

	active_customer = null

	if market:
		market.play_exit_animation("Accept", func():
			market.on_customer_done()
			deal_finished.emit()
		)


func try_haggle() -> void:
	if active_customer == null:
		return
	if not _slider_touched:
		push_warning("PlayerMarket: try_haggle() called before the price slider was touched — ignoring")
		return

	var new_offer := active_customer.evaluate_offer(requested_amount)

	match active_customer.outcome:
		Customer.OfferResult.ACCEPT:
			print("%s: %s" % [active_customer.display_name, active_customer.dialog_text])
			dialog_updated.emit(active_customer.dialog_text)
			accept_deal()
		Customer.OfferResult.REJECT:
			print("%s: %s (might go up to %.2f)" % [active_customer.display_name, active_customer.dialog_text, new_offer])
			dialog_updated.emit(active_customer.dialog_text)
		Customer.OfferResult.WALKAWAY:
			print("%s: %s" % [active_customer.display_name, active_customer.dialog_text])
			dialog_updated.emit(active_customer.dialog_text)
			active_customer = null
			if market:
				market.play_exit_animation("End", func():
					market.on_customer_done()
					deal_finished.emit()
)
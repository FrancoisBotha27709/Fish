extends Player
class_name PlayerMarket

var active_customer : Customer = null
var requested_amount : float = 0.0

## Wire to the "Offer" button's `pressed` signal
@export var market : GameMarket

func start_negotiating(customer : Customer) -> void:
	active_customer = customer
	if not customer.request_random_item(UtilityStates.items):
		print("You have nothing %s wants." % customer.display_name)
		active_customer = null
		return

	requested_amount = active_customer.get_current_offer()
	print("%s wants your %s" % [customer.display_name, customer.ask_item()])
	_configure_slider()

func _configure_slider() -> void:
	if active_customer == null or active_customer.want_item == null:
		return
	var value := active_customer.want_item.get_value()
	# slider.min_value = value * 0.5
	# slider.max_value = value * 2.0
	# slider.value = value

## Wire to the slider's `value_changed` signal
func _on_slider_value_changed(value : float) -> void:
	requested_amount = value


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
		market.play_exit_animation("bought", func(): market.on_customer_done())

func try_haggle() -> void:
	if active_customer == null:
		return

	var new_offer := active_customer.evaluate_offer(requested_amount)

	match active_customer.outcome:
		Customer.OfferResult.ACCEPT:
			print("%s: %s" % [active_customer.display_name, active_customer.dialog_text])
			accept_deal()
		Customer.OfferResult.REJECT:
			print("%s: %s (might go up to %.2f)" % [active_customer.display_name, active_customer.dialog_text, new_offer])
		Customer.OfferResult.WALKAWAY:
			print("%s: %s" % [active_customer.display_name, active_customer.dialog_text])
			active_customer = null
			if market:
				market.play_exit_animation("walkaway", func(): market.on_customer_done())

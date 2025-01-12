# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::ProratedAggregations::UniqueCountService, type: :service do
  subject(:unique_count_service) do
    described_class.new(
      billable_metric:,
      subscription:,
      group:,
      event: pay_in_advance_event,
    )
  end

  let(:subscription) do
    create(
      :subscription,
      started_at:,
      subscription_at:,
      billing_time: :anniversary,
    )
  end

  let(:pay_in_advance_event) { nil }
  let(:options) { {} }
  let(:subscription_at) { DateTime.parse('2022-06-09') }
  let(:started_at) { subscription_at }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'unique_count_agg',
      field_name: 'unique_id',
      recurring: true,
    )
  end

  let(:from_datetime) { DateTime.parse('2022-07-09 00:00:00 UTC') }
  let(:to_datetime) { DateTime.parse('2022-08-08 23:59:59 UTC') }

  let(:added_at) { from_datetime - 1.month }
  let(:removed_at) { nil }
  let(:quantified_event) do
    create(
      :quantified_event,
      customer:,
      added_at:,
      removed_at:,
      external_subscription_id: subscription.external_id,
      billable_metric:,
    )
  end

  before { quantified_event }

  describe '#aggregate' do
    let(:result) { unique_count_service.aggregate(from_datetime:, to_datetime:, options:) }

    context 'with persisted metric on full period' do
      it 'returns the number of persisted metric' do
        expect(result.aggregation).to eq(1)
      end

      context 'when there is persisted event and event added in period' do
        let(:new_quantified_event) do
          create(
            :quantified_event,
            customer:,
            added_at: from_datetime + 10.days,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { new_quantified_event }

        it 'returns the correct number' do
          expect(result.aggregation).to eq((1 + 21.fdiv(31)).ceil(5))
        end
      end

      context 'when subscription was terminated in the period' do
        let(:subscription) do
          create(
            :subscription,
            started_at:,
            subscription_at:,
            billing_time: :anniversary,
            terminated_at: to_datetime,
            status: :terminated,
          )
        end
        let(:to_datetime) { DateTime.parse('2022-07-24 23:59:59') }

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
        end
      end

      context 'when subscription was upgraded in the period' do
        let(:subscription) do
          create(
            :subscription,
            started_at:,
            subscription_at:,
            billing_time: :anniversary,
            terminated_at: to_datetime,
            status: :terminated,
          )
        end
        let(:to_datetime) { DateTime.parse('2022-07-24 23:59:59') }

        before do
          create(
            :subscription,
            previous_subscription: subscription,
            organization:,
            customer:,
            started_at: to_datetime,
          )
        end

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
        end
      end

      context 'when subscription was started in the period' do
        let(:started_at) { DateTime.parse('2022-08-01') }
        let(:from_datetime) { started_at }

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(8.fdiv(31).ceil(5))
        end
      end

      context 'when plan is pay in advance' do
        before do
          subscription.plan.update!(pay_in_advance: true)
        end

        it 'returns the number of persisted metric' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics added in the period' do
      let(:added_at) { from_datetime + 15.days }

      it 'returns the prorata of the full duration' do
        expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
      end

      context 'when added on the first day of the period' do
        let(:added_at) { from_datetime }

        it 'returns the full duration' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics terminated in the period' do
      let(:removed_at) { to_datetime - 15.days }

      it 'returns the prorata of the full duration' do
        expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
      end

      context 'when removed on the last day of the period' do
        let(:removed_at) { to_datetime }

        it 'returns the full duration' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics added and terminated in the period' do
      let(:added_at) { from_datetime + 1.day }
      let(:removed_at) { to_datetime - 1.day }

      it 'returns the prorata of the full duration' do
        expect(result.aggregation).to eq(29.fdiv(31).ceil(5))
      end

      context 'when added and removed the same day' do
        let(:added_at) { from_datetime + 1.day }
        let(:removed_at) { added_at.end_of_day }

        it 'returns a 1 day duration' do
          expect(result.aggregation).to eq(1.fdiv(31).ceil(5))
        end
      end
    end

    context 'when current usage context and charge is pay in arrear' do
      let(:options) do
        { is_pay_in_advance: false, is_current_usage: true }
      end
      let(:new_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { new_quantified_event }

      it 'returns correct result' do
        expect(result.aggregation).to eq((1 + 21.fdiv(31)).ceil(5))
        expect(result.current_usage_units).to eq(2)
      end
    end

    context 'when current usage context and charge is pay in advance' do
      let(:options) do
        { is_pay_in_advance: true, is_current_usage: true }
      end
      let(:previous_event) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 5.days,
          quantified_event: previous_quantified_event,
          properties: {
            unique_id: '000',
          },
          metadata: {
            current_aggregation: '1',
            max_aggregation: '1',
            max_aggregation_with_proration: '0.8',
          },
        )
      end
      let(:previous_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 5.days,
          removed_at:,
          external_id: '000',
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { previous_event }

      it 'returns period maximum as aggregation' do
        expect(result.aggregation).to eq(1.8)
        expect(result.current_usage_units).to eq(2)
      end

      context 'when previous event does not exist' do
        let(:previous_quantified_event) { nil }

        it 'returns only the past aggregation' do
          expect(result.aggregation).to eq(1)
          expect(result.current_usage_units).to eq(1)
        end
      end
    end

    context 'when event is given' do
      let(:properties) { { unique_id: '111' } }
      let(:pay_in_advance_event) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 10.days,
          properties:,
          quantified_event: new_quantified_event,
        )
      end
      let(:new_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { pay_in_advance_event }

      it 'assigns an pay_in_advance aggregation' do
        expect(result.pay_in_advance_aggregation).to eq(21.fdiv(31).ceil(5))
      end

      context 'when event is missing properties' do
        let(:properties) { {} }

        it 'assigns 0 as pay_in_advance aggregation' do
          expect(result.pay_in_advance_aggregation).to be_zero
        end
      end

      context 'when current period aggregation is greater than period maximum' do
        let(:previous_event) do
          create(
            :event,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 5.days,
            quantified_event: previous_quantified_event,
            properties: {
              unique_id: '000',
            },
            metadata: {
              current_aggregation: '7',
              max_aggregation: '7',
              max_aggregation_with_proration: '5.8',
            },
          )
        end
        let(:previous_quantified_event) do
          create(
            :quantified_event,
            customer:,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { previous_event }

        it 'assigns a pay_in_advance aggregation' do
          expect(result.pay_in_advance_aggregation).to eq(21.fdiv(31).ceil(5))
        end
      end

      context 'when current period aggregation is less than period maximum' do
        let(:previous_event) do
          create(
            :event,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 5.days,
            quantified_event: previous_quantified_event,
            properties: {
              unique_id: '000',
            },
            metadata: {
              current_aggregation: '4',
              max_aggregation: '7',
              max_aggregation_with_proration: '5.8',
            },
          )
        end
        let(:previous_quantified_event) do
          create(
            :quantified_event,
            customer:,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { previous_event }

        it 'assigns a pay_in_advance aggregation' do
          expect(result.pay_in_advance_aggregation).to eq(0)
          expect(result.units_applied).to eq(1)
        end
      end
    end
  end
end
